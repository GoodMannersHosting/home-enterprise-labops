# Home Enterprise LabOps (HELO)

We're designing HELO (Home Enterprise LabOps) to bridge the gap between enterprise-grade engineering and real-world accessibility. For many current and future engineers, hands-on experience with enterprise-grade tooling is nearly impossible without access to a corporate tech stack. Traditional homelabs rarely replicate the complexity, constraints, or workflows of enterprise environments, making it difficult to truly prepare for modern DevOps, SRE, or Platform roles.

We aim to change that with HELO by offering a self-hosted, open framework to simulate enterprise-like infrastructure in your own lab! We hope to empower engineers to experiment, break things, and build real-world skills — without needing a badge or budget from a big-name employer.

Whether diving into GitOps, high-availability clusters, or cloud-native tooling, HELO provides a structured playground to level up, on your terms.

HELO: Test Big Ideas in Small Spaces.

## Tools and Technologies

| Category                                | Tools & Technologies                                                                                                                    |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| **Infrastructure & Cluster Management** | ✅ Talos Linux<br>❌ Cluster API<br>❌ Cluster Autoscaler<br>✅ Rook-Ceph<br>✅ Proxmox                                                 |
| **Networking & Service Mesh**           | ✅ Cilium/Hubble<br>✅ Istio<br>✅ Gateway API<br>✅ External DNS<br>✅ PowerDNS                                                        |
| **Security & Identity**                 | ✅ Cert-Manager<br>✅ Keycloak<br>❌ OpenBao<br>✅ SOPS<br>✅ age<br>❌ Validating Admission Policies<br>❌ Mutating Admission Webhooks |
| **Observability & Monitoring**          | ❌ Kube Prometheus Stack<br>❌ Mimir<br>❌ OpenTelemetry                                                                                |
| **GitOps & Delivery**                   | ✅ ArgoCD<br>✅ Helm<br>❌ GoTask<br>✅ Talhelper                                                                                       |
| **Data & Storage**                      | ✅ Cloud Native Postgres<br> ✅ Rook-Ceph<br>❌ Minio                                                                                   |
| **Container Registry**                  | ❌ Harbor                                                                                                                               |
| **Cloud Resource Management**           | ❌ Crossplane<br>❌ Vault Secrets Operator                                                                                              |
