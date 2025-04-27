# PowerDNS

Much of this code has been adopted from [owndomainname/powerdns-stack-over-k8s](https://github.com/owndomainhome/powerdns-stack-over-k8s/tree/main) - give them a star!

## Generating a 128-character secret key

Both options below will generate a 128-character secret key.

```bash
# MacOS - openssl
openssl rand -base64 96 | tr -d '\n'

# MacOS - /dev/urandom
cat /dev/urandom | base64 | tr -dc '0-9a-zA-Z' | head -c128
```
