# Scratchpad Notes and bash commands

## age encryption of the sealed-secret key

```bash
age -i /Users/dan/.config/age/age.txt \
-e -o keys/sealed-secret.key{.enc,}
```

## Kubeseal to encrypt secrets

```bash
kubeseal --cert keys/sealed-secret.crt \
-oyaml -{f,w}=kubernetes/capi/capmox/capmox-manager-credentials.yaml
```
