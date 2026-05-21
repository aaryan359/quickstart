# Deployment Assets

This folder contains the runtime automation for the AWS VMs.

Terraform owns infrastructure in `terraform/`. The files here own what each VM
does after it boots:

- `user-data/api.sh.tftpl` configures Nginx on the public API VM.
- `user-data/engine.sh.tftpl` starts the iii engine and built-in workers.
- `user-data/math.sh.tftpl` starts the Python math worker.
- `user-data/caller.sh.tftpl` starts the TypeScript caller worker.

Terraform will render these templates with the repository URL, branch, install
path, and engine private IP.
