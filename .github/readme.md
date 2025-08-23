# Home Enterprise LabOps (HELO)

I'm designing HELO (Home Enterprise LabOps) to bridge the gap between enterprise-grade engineering and real-world accessibility. For many current and future engineers, hands-on experience with enterprise-grade tooling is nearly impossible without access to a corporate tech stack. Traditional homelabs rarely replicate the complexity, constraints, or workflows of enterprise environments, making it difficult to truly prepare for modern DevOps, SRE, or Platform roles.

I aim to change that with HELO by offering a self-hosted, open framework to simulate enterprise-like infrastructure in your own lab! I hope to empower engineers to experiment, break things, and build real-world skills — without needing a badge or budget from a big-name employer.

Whether diving into GitOps, high-availability clusters, or cloud-native tooling, HELO provides a structured playground to level up, on your terms.

HELO: Test Big Ideas in Small Spaces.

> [!IMPORTANT]
> While this repository originally had Proxmox, Cluster API, and Cluster Autoscaler baked in, I've been forced to abandon that work for now. The additional complexities and operational overhead introduced too many pain points and trade-offs to be worthwhile, and I want this repository to remain maintainable, educational, and focused on its core objectives.

## Tools and Technologies

| Category                                | Tools & Technologies                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Infrastructure & Cluster Management** | [✅ Talos Linux](https://github.com/siderolabs/talos)<br>                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| **Networking & Service Mesh**           | [✅ Cilium/Hubble](https://github.com/cilium/cilium)<br>[✅ Istio](https://istio.io/latest/)<br>[✅ Gateway API](https://gateway-api.sigs.k8s.io/)<br>[✅ External DNS](https://github.com/kubernetes-sigs/external-dns)<br>[✅ PowerDNS](https://www.powerdns.com/)                                                                                                                                                                                                                                                                                   |
| **Security & Identity**                 | [✅ Cert-Manager](https://cert-manager.io/)<br>[✅ SOPS](https://github.com/getsops/sops)<br>[✅ age](https://github.com/FiloSottile/age)<br>[✅ Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)<br>[⚠️ Keycloak](https://www.keycloak.org/)<br>[⚠️ OpenBao](https://openbao.org/)<br>[⚠️ Validating Admission Policies](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/)<br>[❌ Mutating Admission Webhooks](https://kubernetes.io/docs/reference/access-authn-authz/mutating-admission-policy/) |
| **GitOps & Delivery**                   | [✅ Helm](https://helm.sh/)<br>[✅ Talhelper](https://github.com/budimanjojo/talhelper)<br>[✅ ArgoCD](https://argo-cd.readthedocs.io/en/stable/)<br>[⚠️ GoTask](https://github.com/go-task/task)                                                                                                                                                                                                                                                                                                                                                      |
| **Data & Storage**                      | [✅ Cloud Native Postgres](https://cloudnative-pg.io/)<br>[✅ Rook-Ceph](https://rook.io/)                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| **Container Registry**                  | [✅ Harbor](https://goharbor.io/)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| **Cloud Resource Management**           | [❌ Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso)                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| **Observability & Monitoring**          | [❌ Kube Prometheus Stack](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack)<br>[❌ Mimir](https://grafana.com/oss/mimir/)<br>[❌ OpenTelemetry](https://opentelemetry.io/)                                                                                                                                                                                                                                                                                                                                             |
| **AI/ML Tooling**                       | [✅ Open WebUI](https://github.com/open-webui/open-webui)<br>[✅ Ollama](https://ollama.com/)<br>[✅ Docling](https://github.com/docling-project/docling)<br>[✅ n8n](https://n8n.io/)<br>[✅ ComfyUI](https://github.com/comfyanonymous/ComfyUI)<br>[✅ K8S-MCP](https://github.com/Flux159/mcp-server-kubernetes)                                                                                                                                                                                                                                    |
| **CI/CD**                               | [✅ GitHub Action Runner Controller](https://github.com/actions/actions-runner-controller)                                                                                                                                                                                                                                                                                                                                                                                                                                                             |

> [!NOTE]
> ✅ = Completed or Working<br>
> ⚠️ = In Progress or Partially Working<br>
> ❌ = Not Started or Not Working

## Development

The only tools you need to have in order to get started are:

- Homebrew (on MacOS) - [Homebrew](https://brew.sh/)
- go-task (on MacOS) - `brew install go-task`

> [!TIP]
> Other tools will be installed automatically when you run the `task` command.

### Set up your environment

```bash
# Clone the repository
git clone https://github.com/GoodMannersHosting/home-enterprise-labops.git
cd home-enterprise-labops

# On MacOS, make sure you have go-task installed
brew install go-task

# Initalize the environment
task
```
