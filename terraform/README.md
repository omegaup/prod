# Releasing a new runner image

```shell
TF_VAR_az_runner_image=true terraform plan -out=tfplan
terraform apply tfplan
while true; do
  vm_state="$(az vm show \
    --resource-group omegaup-runner-image-builder \
    --name omegaup-runner-image-builder \
    --show-details | jq -r '.powerState')"
  if [[ "${vm_state}" == "VM stopped" ]]; then
    break
  fi
  echo "${vm_state}"
  sleep 10
done
az vm generalize \
  --resource-group omegaup-runner-image-builder \
  --name omegaup-runner-image-builder
az image create \
  --resource-group omegaup-runner-image-builder \
  --source omegaup-runner-image-builder \
  --name "omegaup-runner-image-$(date '+%Y%m%d')"
```

Then update the `terraform/runner_image.tf`'s `azurerm_image.runner` and
`azurerm_shared_image_version.runner` to the new values.
