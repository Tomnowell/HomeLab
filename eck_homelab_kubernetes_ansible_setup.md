# ECK Homelab Kubernetes Setup (Terraform + Ansible)

You already have a solid foundation. The main things missing before you can cleanly install the ECK operator are:

- proper cluster join automation
- a CNI/network plugin
- kubeconfig handling
- worker join playbook
- some Kubernetes prerequisites for Elasticsearch
- a cleaner inventory structure
- optional storage class support

The following setup gets you to a reliable baseline Kubernetes cluster suitable for following the official Elastic ECK documentation.

---

# Recommended File Structure

```text
ansible/
├── inventory/
│   └── hosts.ini
├── playbooks/
│   ├── bootstrap_k8s.yml
│   ├── control_plane_init.yml
│   ├── join_workers.yml
│   ├── install_flannel.yml
│   ├── prepare_eck_nodes.yml
│   └── site.yml
└── ansible.cfg
```

---

# inventory/hosts.ini

Update your inventory to look like this:

```ini
[k8s_control]
k8s-master ansible_host=192.168.1.10

[k8s_workers]
k8s-worker-1 ansible_host=192.168.1.11
k8s-worker-2 ansible_host=192.168.1.12

[k8s_cluster:children]
k8s_control
k8s_workers

[k8s_cluster:vars]
ansible_user=ubuntu
ansible_python_interpreter=/usr/bin/python3
```

Replace the IPs with your Terraform-assigned addresses.

---

# ansible.cfg

```ini
[defaults]
inventory = ./inventory/hosts.ini
host_key_checking = False
retry_files_enabled = False
stdout_callback = yaml
```

---

# Improved bootstrap_k8s.yml

Your original bootstrap playbook is good, but I recommend these changes:

- install required kernel modules persistently
- configure containerd correctly for Kubernetes
- ensure swap stays disabled after reboot
- install utilities useful for debugging
- configure br_netfilter correctly

Replace your current playbook with this:

```yaml
---
- name: Bootstrap Kubernetes Nodes
  hosts: k8s_cluster
  become: true

  vars:
    kubernetes_version: "1.30"

  tasks:

    - name: Update apt cache and upgrade packages
      apt:
        update_cache: yes
        upgrade: dist

    - name: Install prerequisite packages
      apt:
        name:
          - apt-transport-https
          - ca-certificates
          - curl
          - gpg
          - software-properties-common
          - qemu-guest-agent
          - containerd
          - jq
          - vim
          - net-tools
        state: present

    - name: Enable qemu guest agent
      systemd:
        name: qemu-guest-agent
        enabled: true
        state: started

    - name: Disable swap immediately
      command: swapoff -a
      when: ansible_swaptotal_mb > 0

    - name: Disable swap permanently
      replace:
        path: /etc/fstab
        regexp: '^([^#].*\sswap\s.*)$'
        replace: '# \1'

    - name: Load required kernel modules
      copy:
        dest: /etc/modules-load.d/k8s.conf
        content: |
          overlay
          br_netfilter

    - name: Load overlay module
      modprobe:
        name: overlay
        state: present

    - name: Load br_netfilter module
      modprobe:
        name: br_netfilter
        state: present

    - name: Configure Kubernetes sysctl settings
      copy:
        dest: /etc/sysctl.d/k8s.conf
        content: |
          net.bridge.bridge-nf-call-iptables = 1
          net.bridge.bridge-nf-call-ip6tables = 1
          net.ipv4.ip_forward = 1

    - name: Apply sysctl settings
      command: sysctl --system

    - name: Create containerd config directory
      file:
        path: /etc/containerd
        state: directory

    - name: Generate default containerd config
      shell: |
        containerd config default > /etc/containerd/config.toml
      args:
        creates: /etc/containerd/config.toml

    - name: Enable SystemdCgroup
      replace:
        path: /etc/containerd/config.toml
        regexp: 'SystemdCgroup = false'
        replace: 'SystemdCgroup = true'

    - name: Restart containerd
      systemd:
        name: containerd
        state: restarted
        enabled: true

    - name: Create apt keyring directory
      file:
        path: /etc/apt/keyrings
        state: directory
        mode: '0755'

    - name: Download Kubernetes signing key
      shell: |
        curl -fsSL https://pkgs.k8s.io/core:/stable:/v{{ kubernetes_version }}/deb/Release.key \
        | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      args:
        creates: /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    - name: Add Kubernetes repository
      copy:
        dest: /etc/apt/sources.list.d/kubernetes.list
        content: |
          deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v{{ kubernetes_version }}/deb/ /

    - name: Install Kubernetes packages
      apt:
        update_cache: yes
        name:
          - kubelet
          - kubeadm
          - kubectl
        state: present

    - name: Hold Kubernetes packages
      dpkg_selections:
        name: "{{ item }}"
        selection: hold
      loop:
        - kubelet
        - kubeadm
        - kubectl

    - name: Enable kubelet
      systemd:
        name: kubelet
        enabled: true
        state: started
```

---

# Improved control_plane_init.yml

This version:

- initializes the cluster properly
- installs Flannel automatically
- exports the join command for workers
- ensures kubectl works for the ubuntu user

```yaml
---
- name: Initialize Kubernetes Control Plane
  hosts: k8s_control
  become: true

  tasks:

    - name: Initialize Kubernetes cluster
      shell: |
        kubeadm init \
          --pod-network-cidr=10.244.0.0/16
      args:
        creates: /etc/kubernetes/admin.conf

    - name: Create .kube directory
      file:
        path: /home/ubuntu/.kube
        state: directory
        owner: ubuntu
        group: ubuntu
        mode: '0755'

    - name: Copy admin.conf to ubuntu kube config
      copy:
        src: /etc/kubernetes/admin.conf
        dest: /home/ubuntu/.kube/config
        remote_src: true
        owner: ubuntu
        group: ubuntu
        mode: '0644'

    - name: Install Flannel CNI
      become_user: ubuntu
      environment:
        KUBECONFIG: /home/ubuntu/.kube/config
      shell: |
        kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

    - name: Generate worker join command
      shell: kubeadm token create --print-join-command
      register: join_command

    - name: Save join command locally
      local_action:
        module: copy
        content: "{{ join_command.stdout }}"
        dest: ./join-command.sh
      become: false
```

---

# New join_workers.yml

Create this new playbook:

```yaml
---
- name: Join worker nodes to cluster
  hosts: k8s_workers
  become: true

  tasks:

    - name: Copy join command to workers
      copy:
        src: ./join-command.sh
        dest: /tmp/join-command.sh
        mode: '0755'

    - name: Join cluster
      shell: |
        /tmp/join-command.sh
      args:
        creates: /etc/kubernetes/kubelet.conf
```

---

# New prepare_eck_nodes.yml

Elasticsearch has additional Linux requirements.

Create this playbook:

```yaml
---
- name: Prepare nodes for Elasticsearch
  hosts: k8s_cluster
  become: true

  tasks:

    - name: Set vm.max_map_count
      sysctl:
        name: vm.max_map_count
        value: '262144'
        state: present
        reload: yes
```

This is REQUIRED for Elasticsearch.

---

# New site.yml

This gives you a single orchestration entry point.

```yaml
---
- import_playbook: bootstrap_k8s.yml
- import_playbook: control_plane_init.yml
- import_playbook: join_workers.yml
- import_playbook: prepare_eck_nodes.yml
```

---

# Recommended Execution Order

From your ansible directory:

```bash
ansible-playbook playbooks/site.yml
```

Or manually:

```bash
ansible-playbook playbooks/bootstrap_k8s.yml
ansible-playbook playbooks/control_plane_init.yml
ansible-playbook playbooks/join_workers.yml
ansible-playbook playbooks/prepare_eck_nodes.yml
```

---

# Verify the Cluster

SSH into the control plane node:

```bash
kubectl get nodes
```

You should see:

```text
NAME             STATUS   ROLES           AGE   VERSION
k8s-master       Ready    control-plane   ...   ...
k8s-worker-1     Ready    <none>          ...   ...
k8s-worker-2     Ready    <none>          ...   ...
```

Then verify system pods:

```bash
kubectl get pods -A
```

Everything should eventually become Running.

---

# Storage Considerations for ECK

This is important.

ECK works best with persistent storage.

For a homelab, the simplest options are:

1. local-path-provisioner (recommended)
2. Longhorn
3. OpenEBS
4. NFS-backed storage

For your first deployment, I strongly recommend:

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
```

Then:

```bash
kubectl get storageclass
```

You should see:

```text
local-path
```

This is enough for a small ECK lab.

---

# After Kubernetes is Ready

You can then follow the official Elastic ECK installation docs.

The usual next steps are:

```bash
kubectl create -f https://download.elastic.co/downloads/eck/3.1.0/crds.yaml

kubectl apply -f https://download.elastic.co/downloads/eck/3.1.0/operator.yaml
```

Then deploy an Elasticsearch cluster manifest.

---

# Important Homelab Advice

For a 3-node homelab cluster:

- use ONE control plane only
- avoid HA etcd initially
- keep resource requests conservative
- start with a 1-node Elasticsearch cluster
- use small JVM heaps (1-2 GB)
- do not overcommit RAM

A good starter ECK topology is:

- 1 Elasticsearch node
- 1 Kibana instance
- no Fleet Server initially

Once stable:

- add more data nodes
- add snapshots
- add monitoring
- add ingress
- add cert-manager

---

# Suggested Next Improvements

Once the cluster works, the next major improvements are:

- migrate from Flannel to Cilium
- use MetalLB for LoadBalancer services
- install ingress-nginx
- add cert-manager
- use sealed-secrets or external-secrets
- add Terraform provisioning for the Kubernetes layer itself
- move to Ansible roles
- add Talos or immutable node designs later

---

# Architecture Note

Your current design direction is actually very sensible for learning:

Terraform:
- VM provisioning
- networking
- storage

Ansible:
- OS bootstrap
- Kubernetes installation
- node configuration

Kubernetes:
- orchestration
- ECK
- observability stack
- future services

That separation scales very well as your homelab grows.

