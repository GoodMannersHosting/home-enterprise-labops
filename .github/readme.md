# HELO: Home Enterprise LabOps

**Test Big Ideas in Small Spaces.**

I built HELO because enterprise-grade tooling is usually locked behind corporate firewalls. If you want to learn GitOps, service meshes, or production Kubernetes, without a badge or a budget, this is your playground.

HELO is a self-hosted, production-like infrastructure you can spin up in your own lab. It's designed to be broken, rebuilt, and learned from. Everything is version-controlled and declarative, so you can experiment without fear.

> **Note:** I originally had Proxmox and Cluster API baked into this. I've abandoned that work for now. The operational overhead was killing the educational value, and I want HELO to stay maintainable and focused.

## What's Actually Working

Here's the status of what's deployed and functioning:

### Infrastructure

| Tool | Status |
|------|--------|
| [Talos Linux](https://github.com/siderolabs/talos) | ✅ Working |
| [Cilium + Hubble](https://github.com/cilium/cilium) | ✅ Working |
| [Istio](https://istio.io/latest/) | ✅ Working |
| [CoreDNS](https://github.com/coredns/coredns) | ✅ Working |
| [Gateway API](https://gateway-api.sigs.k8s.io/) | ✅ Working |

### GitOps & Deployment

| Tool | Status |
|------|--------|
| [ArgoCD](https://argo-cd.readthedocs.io/en/stable/) | ✅ Working |
| [Helm](https://helm.sh/) | ✅ Working |
| [TOPF](https://postfinance.github.io/topf/main/) | ✅ Working |
| [GitHub Action Runner Controller](https://github.com/actions/actions-runner-controller) | ✅ Working |

### Networking & DNS

| Tool | Status |
|------|--------|
| [External DNS](https://github.com/kubernetes-sigs/external-dns) | ✅ Working |

### Security & Identity

| Tool | Status |
|------|--------|
| [Cert-Manager](https://cert-manager.io/) | ✅ Working |
| [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) | ✅ Working |
| [External Secrets Operator](https://github.com/external-secrets/external-secrets) | ✅ Working |
| [Keycloak](https://www.keycloak.org/) | ✅ Working |

### Storage & Data

| Tool | Status |
|------|--------|
| [Rook-Ceph](https://rook.io/) | ✅ Working |
| [Cloud Native Postgres](https://cloudnative-pg.io/) | ✅ Working |

### Observability

| Tool | Status |
|------|--------|
| [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator) | ✅ Working |
| [Gatus](https://gatus.io/) | ✅ Working |

### AI/ML Stack

| Tool | Status |
|------|--------|
| [Open WebUI](https://github.com/open-webui/open-webui) | ✅ Working |
| [LiteLLM Operator](https://github.com/BerriAI/litellm) | ✅ Working |
| [LLM Router](https://github.com/litellm-ai/llm-router) | ✅ Working |
| [ComfyUI](https://github.com/comfyanonymous/ComfyUI) | ✅ Working |

### Other Services

| Tool | Status |
|------|--------|
| [Harbor](https://goharbor.io/) | ✅ Working |
| [Argo Workflows](https://github.com/argoproj/argo-workflows) | ✅ Working |
| Valheim Server | ✅ Working |

### In Progress

| Tool | Status |
|------|--------|
| Validating Admission Policies | ⚠️ In Progress |
| [Fission](https://fission.io/) | ⚠️ In Progress |
| Intel/NVIDIA GPU inference (llama.cpp) | ⚠️ In Progress |

### Not Started

| Tool | Status |
|------|--------|
| Mutating Admission Webhooks | ❌ Not Started |
| [Mimir](https://grafana.com/oss/mimir/) | ❌ Not Started |
| [OpenTelemetry](https://opentelemetry.io/) | ❌ Not Started |

## Technology Decisions

### Why TOPF over Proxmox/Cluster API?

I spent a lot of time fighting with Proxmox and Cluster API. They're what I wanted to use and how I believe is a more apt comparison to Enterprise environments, but for homelab usage, it's unfortunately fare more complexity and effort than it's worth in educational value. [TOPF Talos Orchestrator by PostFinance](https://github.com/postfinance/topf) running on baremetal hardware gives me:

- Simpler cluster lifecycle management
- GitOps-first approach that aligns with everything else
- Less magic, more verbosity transparency

It fits better for a homelab learning environment (and when I'm exhausted from a day at the office and my brain is cooked) where understanding what's happening matters more than the abstraction of an enterprise environment.

### GPU inference with llama.cpp

Both the Intel and NVIDIA GPU inference workloads use llama.cpp. The directory names still say vLLM (an artifact of "I'm sure I can get that working the way I want!"). llama.cpp is simpler to deploy, works across multiple GPU architectures, and uses far less memory. For experimenting and learning in a home lab, llama.cpp is far more practical than vLLM.

### Why LiteLLM + OpenWebUI for AI tooling?

This combination gives me a production-like AI infrastructure:

- **LiteLLM** provides a unified API across multiple model providers (OpenAI, Anthropic, local models)
- **Open WebUI** offers a feature-rich chat interface with document processing
- Together they simulate what a company would deploy, making it great for learning

> [!NOTE]
> Serious shout out to [@coolguy1771](https://github.com/coolguy1771) for getting LiteLLM working and doing a _lot_ of tuning for the NVIDIA Models and deployment.

### Why Cilium with BGP?

Cilium's eBPF-based networking is fast and observable. Adding BGP integration means the cluster can dynamically advertise routes to the rest of the network, which is what you want/need in an enterprise environment. It's a great way to learn real-world networking concepts.

## What Lives Elsewhere

The following services run in my [Cloud Security Cluster](https://github.com/GoodMannersHosting/cloud-security-cluster) repo, which complements HELO with enterprise security tooling:

| Tool | Purpose |
|------|---------|
| [Authentik](https://goauthentik.io/) | Enterprise identity provider with SSO |
| [OpenBao](https://openbao.org/) | Secrets management (auto-unsealed via AWS KMS) |
| [Doco-CD](https://github.com/digitalocean/doco-cd) | GitOps for Docker Compose stacks |
| [PowerDNS](https://www.powerdns.com/) | Authoritative and recursive DNS |
| [DNSweaver](https://dnsweaver.net/) | DNS filtering and ad blocking |
| [Traefik](https://traefik.io/) | Dynamic ingress with TLS |

## Getting Started

You'll need:
- A Talos Linux cluster (see the infrastructure/ directory)
- Basic familiarity with Kubernetes concepts
- Patience. These things take time to spin up.

```bash
# Clone the repo
git clone https://github.com/GoodMannersHosting/home-enterprise-labops.git
cd home-enterprise-labops

# Set up your environment (MacOS)
brew install go-task
task
```

From there, explore the `kubernetes/` directory to see what's deployed. Everything is version-controlled and documented.

## Questions?

Feel free to ping me at daniel.a.manners@gmail.com. If something doesn't make sense, that's on me.

> [!TIP]
> Please let me know what needs clarification and I'll get docs updated. Thank you!
