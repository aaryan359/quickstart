# iii Inference AWS Deployment

This repository deploys an iii-based inference API across AWS EC2 instances in a VPC. A public API VM accepts JSON HTTP requests, forwards them to the iii HTTP worker, and the request flows through a TypeScript caller worker to a Python inference worker over private RPC.

## Architecture

```text
Internet
   |
   | HTTP POST /v1/chat/completions
   v
Public subnet: 10.0.1.0/24
+-----------------------------+
| API VM                      |
| public IP from Terraform    |
| private IP 10.0.1.10        |
| Nginx reverse proxy :80     |
+-------------+---------------+
              |
              | private HTTP to 10.0.2.10:3111
              v
Private subnet: 10.0.2.0/24
+-----------------------------+
| Engine VM                   |
| private IP 10.0.2.10        |
| iii engine :49134           |
| iii-http :3111              |
| iii-state file store        |
+-------------+---------------+
              |
              | iii RPC over private WebSocket
              v
+-----------------------------+        +-----------------------------+
| Caller worker VM            |        | Inference worker VM         |
| private IP 10.0.2.30        |        | private IP 10.0.2.20        |
| TypeScript worker           | -----> | Python Transformers worker  |
| inference::get_response     |        | inference::run_inference    |
+-----------------------------+        +-----------------------------+
```

Only the API VM is public. The engine, caller worker, and inference worker are in the private subnet and communicate inside the VPC.

## API

Endpoint:

```text
POST /v1/chat/completions
```

Request:

```json
{
  "messages": [
    {
      "role": "user",
      "content": "Say hello in one short sentence."
    }
  ]
}
```

Example:

```bash
curl -X POST http://<api_public_ip>/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Say hello in one short sentence."}]}'
```

Sample response:

```json
{
  "model": "ggml-org/gemma-3-270m-GGUF",
  "message": {
    "role": "assistant",
    "content": "Hello, friend."
  },
  "running_total": 1
}
```

`running_total` is persisted by `iii-state`, so it increases as requests are processed.

## Repository Layout

```text
terraform/                 AWS VPC, subnet, firewall, NAT gateway, and EC2 resources
deploy/user-data/          EC2 startup templates for API, engine, caller, and inference VMs
workers/caller-worker/     TypeScript RPC and HTTP bridge worker
workers/inference-worker/  Python Transformers/GGUF inference worker
config.engine.yaml         Engine config used in AWS
config.yaml                Local quickstart config
```

## Instance Sizing

The API, engine, and caller VMs default to `t3.micro`. The inference VM defaults to `t3.large` because PyTorch, Transformers, and the model require much more memory than a `t3.micro` provides.

`t3.micro` is not a good fit for the inference worker. It has about 1 GiB of RAM, and installing/running PyTorch plus a model can hang, swap heavily, or fail. For a smoother CPU-only demo, use at least `t3.large`; for production inference, use a properly sized CPU or GPU instance.

## Redeploy From Scratch

Prerequisites:

- AWS CLI configured with credentials: `aws configure`
- Terraform installed
- An EC2 key pair already created in AWS
- This repository pushed to GitHub

Create your Terraform values:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region              = "eu-north-1"
availability_zone       = "eu-north-1a"
instance_type           = "t3.micro"
inference_instance_type = "t3.large"
project_name            = "iii-quickstart"

ssh_key_name = "quickstart-key"
my_ip_cidr   = "0.0.0.0/0"

repo_url = "https://github.com/aaryan359/quickstart.git"
repo_ref = "main"
```

For production, replace `0.0.0.0/0` with your own public IP in CIDR form, for example `14.139.240.252/32`.

Deploy:

```bash
terraform init
terraform plan
terraform apply
```

Terraform prints `api_public_ip`. Wait several minutes for cloud-init to install dependencies, download the model, and start services, then test:

```bash
../deploy/check.sh <api_public_ip>
```

Manual curl test:

```bash
curl -X POST http://<api_public_ip>/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Say hello in one short sentence."}]}'
```

Destroy when finished:

```bash
terraform destroy
```

The NAT gateway and larger inference instance can incur cost, so destroy the stack when it is not in use.

## Operations

SSH to the public API VM:

```bash
ssh -A -i quickstart-key.pem ubuntu@<api_public_ip>
```

From the API VM, reach private VMs:

```bash
ssh ubuntu@10.0.2.10  # engine
ssh ubuntu@10.0.2.20  # inference
ssh ubuntu@10.0.2.30  # caller
```

Useful logs:

```bash
sudo tail -n 200 /var/log/cloud-init-output.log
sudo systemctl status nginx --no-pager
sudo systemctl status iii-engine --no-pager
sudo systemctl status iii-inference-worker --no-pager
sudo systemctl status iii-caller-worker --no-pager
sudo journalctl -u iii-inference-worker -n 100 --no-pager
```

## Production Hardening

Before production, I would put the API VM behind an AWS Application Load Balancer with HTTPS, restrict SSH to a trusted IP or replace SSH with AWS Systems Manager Session Manager, and move logs/metrics into CloudWatch. I would also add health checks, least-privilege IAM roles, automated CI/CD, immutable image builds, secret management, backups for state, and tighter security group rules between exact services instead of broad internal TCP.

For reliability, I would run more than one API and worker instance across multiple Availability Zones, use managed storage for state instead of a local file, and add alarms for failed systemd services, high latency, model load failures, and HTTP error responses.

## If The Model Were 100x Larger

If the model were 100x larger, I would separate model serving from the worker orchestration. The model server would run on GPU or high-memory instances, probably behind an internal load balancer, and workers would call it over private networking. I would add model artifact storage in S3, warmup logic, request batching, autoscaling, queue-based backpressure, and observability around token latency, memory usage, and GPU utilization.

For a larger system, I would also consider containers on ECS or EKS so model-serving nodes, API nodes, and worker replicas can be deployed and scaled independently.
