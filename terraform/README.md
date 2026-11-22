# Releasing a new runner image

Use a fresh builder VM created with the current cloud-config. The builder stays
running so Run Command can validate it before capture. Do not restart or modify
it between validation and capture.

Prerequisites: Bash 4+, Terraform ≥ 1.1, Azure CLI, GNU `timeout`. The operator
needs Azure permissions for Run Command, VM lifecycle, and image creation.

```bash
timeout --kill-after=30s 60m bash -s <<'BASH'
set -euo pipefail
TF_VAR_az_runner_image=true terraform plan -out=tfplan
terraform apply tfplan

vm_args=(--resource-group omegaup-runner-image-builder --name omegaup-runner-image-builder)
power_query="instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]"
deadline=$((SECONDS + 300))
while true; do
  agent_state="$(timeout --kill-after=10s 60s az vm get-instance-view "${vm_args[@]}" \
    --query "instanceView.vmAgent.statuses[?code=='ProvisioningState/succeeded'].code | [0]" \
    --output tsv)"
  if [[ "$agent_state" == ProvisioningState/succeeded ]]; then
    break
  fi
  ((SECONDS < deadline)) || { echo 'Timed out waiting for the VM agent' >&2; exit 1; }
  sleep 10
done

power_state="$(timeout --kill-after=10s 60s az vm get-instance-view "${vm_args[@]}" \
  --query "$power_query" --output tsv)"
[[ "$power_state" == PowerState/running ]]

token="OMEGAUP_BUILD_OK_${BASHPID}_${RANDOM}_${RANDOM}_${RANDOM}_${RANDOM}"
result="$(timeout --kill-after=30s 35m az vm run-command invoke "${vm_args[@]}" \
  --command-id RunShellScript --parameters "$token" --scripts '
set -eu
timeout --kill-after=10s 30m cloud-init status --wait --long >/dev/null
status="$(cloud-init status)"
test "$status" = "status: done"
test -f /run/omegaup-image-build-success
for d in root root/home root-compilers root-compilers/home policies; do
  test -d "/var/lib/omegajail/$d"
done
test -x /var/lib/omegajail/bin/omegajail
test -x /var/lib/omegajail/bin/omegajail-setup
test -x /var/lib/omegajail/bin/omegajail-cgroups-wrapper
test -x /usr/bin/omegaup-runner
test -s /lib/fluent-bit/out_newrelic-linux-amd64-1.12.1.so
systemctl is-enabled --quiet fluent-bit
systemctl is-enabled --quiet omegaup-runner
printf "%s\n" "$1"
' --query "value[?code=='ComponentStatus/StdOut/succeeded' || code=='ProvisioningState/succeeded'].[code,message]" \
  --output tsv)"

# Linux may wrap both streams in one message; accept the token only in stdout.
validated=false
stream=none
while IFS= read -r line; do
  case "$line" in
    ComponentStatus/StdOut/succeeded$'\t'*)
      stream=stdout
      line="${line#*$'\t'}"
      ;;
    ProvisioningState/succeeded$'\t'*) stream=waiting ;;
    '[stdout]')
      if [[ "$stream" == waiting ]]; then stream=stdout; fi
      ;;
    '[stderr]') stream=stderr ;;
  esac
  if [[ "$stream" == stdout && "$line" == "$token" ]]; then
    validated=true
  fi
done <<<"$result"
if [[ "$validated" != true ]]; then
  printf 'Guest validation was not confirmed:\n%s\n' "$result" >&2
  exit 1
fi

timeout --kill-after=30s 10m az vm deallocate "${vm_args[@]}"
power_state="$(timeout --kill-after=10s 60s az vm get-instance-view "${vm_args[@]}" \
  --query "$power_query" --output tsv)"
[[ "$power_state" == PowerState/deallocated ]]
timeout --kill-after=30s 5m az vm generalize "${vm_args[@]}"
timeout --kill-after=30s 15m az image create \
  --resource-group omegaup-runner-image-builder \
  --source omegaup-runner-image-builder \
  --name "omegaup-runner-image-$(date '+%Y%m%d')"
BASH
```

The guest check waits for cloud-init to finish (Azure provisioning success alone
is not sufficient), then verifies the success marker, rootfs directories,
executables, and enabled services before emitting the per-invocation token. Any
error or timeout aborts before the next step.

A local timeout does not necessarily stop the guest-side command. On
validation failure, leave the builder running for diagnosis. It continues
to incur charges until explicitly deallocated or deleted.

After capturing the image, add a **new** `azurerm_shared_image_version` resource
in `runner_image.tf` for the new version. Do not modify the existing resource's
`name` in-place — the Azure provider treats it as ForceNew and would destroy the
previous gallery version. Use a `moved` block or `terraform state mv` when
renaming an existing resource address. Always inspect the plan before applying;
it must not contain a destroy for any previous gallery version.

# Rolling back to the previous runner image

If the new image fails during canary or after full rollout, revert to the last
known-good gallery version:

1. **Identify the previous version.**
   The old `azurerm_shared_image_version` resource is still in state. Confirm
   it is available:
   ```bash
   az sig image-version list \
     --resource-group omegaup-runner-image-builder \
     --gallery-name omegaup_runner \
     --gallery-image-definition omegaup-runner-image-20250222 \
     --output table
   ```

2. **Point the VMSS back to the previous version.**
   If the VMSS `source_image_id` is managed in Terraform, change it to
   reference the old resource and apply:
   ```bash
   TF_VAR_az_runner_image=false terraform plan -out=tfplan
   terraform apply tfplan
   ```
   Otherwise use `az vmss update` directly:
   ```bash
   az vmss update \
     --resource-group omegaup-runner \
     --name omegaup-runner-vmss \
     --set "virtualMachineProfile.storageProfile.imageReference.id=<previous_version_resource_id>"
   ```

3. **Reimage the affected instances.**
   ```bash
   az vmss reimage --resource-group omegaup-runner --name omegaup-runner-vmss
   ```
   For a targeted rollback (canary only):
   ```bash
   az vmss reimage --resource-group omegaup-runner --name omegaup-runner-vmss \
     --instance-ids <canary_instance_id>
   ```

4. **Verify recovery.**
   ```bash
   az vmss list-instances \
     --resource-group omegaup-runner --name omegaup-runner-vmss \
     --query "[].{name:name, imageRef:storageProfile.imageReference.id}" \
     --output table
   ```
   Run synthetic rk, kj, kp, and general-language submissions to confirm.

5. **Retain the failed image.**
   Do not delete the failed gallery version or builder VM. Keep both for
   post-mortem.
