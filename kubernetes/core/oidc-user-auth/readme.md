# OIDC User Auth

Before configuring Talos OIDC auth ( [`05-cluster-apiserver-args.yaml`](../../../infrastructure/topf/control-plane/05-cluster-apiserver-args.yaml) and [`10-cluster-apiserver-certsans.yaml`](../../../infrastructure/topf/control-plane/10-cluster-apiserver-certsans.yaml)), ensure your Authentik instance is set up for OIDC. Follow the instructions in our [blog post on configuring Authentik for Kubernetes](https://blog.example.com/authentik-k8s-oidc) to create an application, set up client credentials, and configure user/group mappings.

Once Authentik is configured and you've installed [int128/kubelogin](https://github.com/int128/kubelogin), you can configure OIDC user authentication with the following command:

```bash
kubectl config set-credentials oidc \
  --exec-api-version=client.authentication.k8s.io/v1 \
  --exec-interactive-mode=Never \
  --exec-command=kubectl \
  --exec-arg=oidc-login \
  --exec-arg=get-token \
  --exec-arg="--oidc-issuer-url=https://auth.goodmanners.services/application/o/kubernetes-helo/" \
  --exec-arg="--oidc-client-id=helo-k8s" \
  --exec-arg="--oidc-extra-scope=profile" \
  --exec-arg="--oidc-extra-scope=email"
```

# Applying the Cluster Admin Role

You can reference the [`cluster-admin-role.yaml`](./cluster-admin-role.yaml) file to apply the Cluster Admin role to map the IdP group `helo-admins`.

> [!TIP]
> You should _ALWAYS_ map locked-down groups, avoid using a global cluster-admin permission/role. The mapped file is purely for reference.
