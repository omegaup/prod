# Releasing a new runner image

Use a fresh builder created with the current cloud-config. The builder stays
running so Run Command can validate it before deallocation and capture. Do not
restart or modify it between validation and capture.

Run this from the Terraform directory on a machine with Bash 4+, Terraform, Azure
CLI, and GNU `timeout` (coreutils). Neither `jq`, `openssl`, nor an SSH private
key is required on the operator machine. The operator needs Azure permissions
for Run Command, VM lifecycle operations, and image creation; the VM agent needs
outbound connectivity to Azure.

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

Azure provisioning success is not proof that cloud-init succeeded. The guest
check requires a zero exit status from cloud-init and its final `status: done`
output, rather than assuming a version-specific JSON schema. It then checks the
ephemeral success marker, filesystems, executable, and enabled services before
emitting the per-invocation token.

Any error or timeout aborts the release before the next operation. A local
timeout does not necessarily cancel a remote command. On validation failure,
leave the builder available for diagnosis and do not generalize or capture it;
it continues to incur charges until explicitly cleaned up. These checks do not
replace the separate Omegajail compile/run smoketest on the candidate image.

Then update the `terraform/runner_image.tf`'s `azurerm_image.runner` and
`azurerm_shared_image_version.runner` to the new values.
