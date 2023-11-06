# omegaUp infrastructure as code

This repository contains omegaUp production settings and configuration.

## Updating secrets

Secrets are encrypted using [KSOPS](https://github.com/viaduct-ai/kustomize-sops) with an encryption
key stored in [Amazon Key Management Service](https://aws.amazon.com/kms/).

In order to update a manifest with secrets:

1. Install [SOPS](https://github.com/getsops/sops).
2. Get access to production AWS and [sign in using the
   cli](https://docs.aws.amazon.com/signin/latest/userguide/command-line-sign-in.html).
3. Edit the file using SOPS:
   ```shell
   $ sops k8s/omegaup/overlays/production/frontend/frontend-secret.yaml
   ```
