# Module 0: Foundation

Everything later in the lab sits on top of this: a place to keep Terraform state, a private network,
an encryption key, and a budget alert so a forgotten resource can't quietly run up a bill.

## What gets built

| Stack | Resources | Why |
|---|---|---|
| `bootstrap/` | S3 bucket (versioned, encrypted, private, HTTPS-only) and a generated `backend.hcl` | Remote state for every other stack |
| `foundation/` | VPC with 2 private subnets, private route table, S3 gateway endpoint, locked default SG | Private network for Lambda/RAG later |
| | KMS key with rotation + alias `alias/cpl-main` | Encrypt data with a key you control |
| | AWS Budget ($20/month) with 3 email alerts | Cost guardrail |

Cost: the KMS key is about $1/month, everything else here is free.

## Concepts

### Terraform state, and why it lives in S3
Terraform keeps a state file that maps your code (`aws_vpc.main`) to real resources (`vpc-0abc…`). Without
it, Terraform can't tell what already exists. Kept on a laptop, state gets lost or out of sync as soon as
two people (or a laptop and a CI pipeline) work on the same stack. So teams keep it in S3:

- **Versioning** keeps every past copy, so a bad write can be rolled back.
- **Locking** stops two `terraform apply` runs from writing at the same time. Since Terraform 1.10, the S3
  backend does this itself with a `.tflock` object (`use_lockfile = true`). Older setups needed a DynamoDB table.
- **Encryption + blocked public access + HTTPS-only policy**: state often contains secrets, so the bucket is treated as sensitive.

The bootstrap stack is a chicken-and-egg exception. It creates the bucket, so its own state has to stay local.

### Partial backend configuration
A `backend` block can't use variables, and the bucket name contains your account ID. So each stack only
sets its `key` (its own path inside the bucket), and the rest comes from `backend.hcl` at init time:
`terraform init -backend-config=../../backend.hcl`. One file, generated once, used everywhere.

### Private subnets and VPC endpoints
A subnet is "private" because of its route table, not because of its name. This one has only the implicit
`local` route, with no internet gateway and no NAT. Resources inside can talk to each other and to nothing else.

To reach AWS services anyway, you use **VPC endpoints**:
- **Gateway endpoints** (S3, DynamoDB only) add a route to the service's IP prefix list. They're free.
- **Interface endpoints** (PrivateLink) put a private IP for the service (Bedrock, STS, ...) inside your subnet.
  They cost about $0.01/hour per AZ. You'll use them in Module 7 to keep the RAG stack fully private.

### KMS customer-managed keys
AWS encrypts most things by default with AWS-managed keys. A **customer-managed key** adds control:
the key policy says who may use it, you can disable it, rotation is under your control, and every
encrypt/decrypt call shows up in CloudTrail. The `EnableIAMPolicies` statement delegates access decisions
to IAM. Without it nobody, not even the root user, could manage the key.

### Budgets
AWS Budgets checks spend a few times a day and emails you at 50% and 80% of actual spend, and when
the *forecast* goes over 100%. It's an early warning, not a hard stop.

## Run it

Prerequisites (one time, in WSL):

```bash
# Terraform 1.10+
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform unzip

# AWS CLI v2
curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip

aws configure            # or: aws configure sso
aws sts get-caller-identity
terraform version        # must be 1.10 or newer
```

**1. Bootstrap the state bucket**
```bash
cd 00-foundation/bootstrap
terraform init
terraform apply
```
Check that `backend.hcl` now exists at the repo root: `cat ../../backend.hcl`.

**2. Foundation**
```bash
cd ../foundation
terraform init -backend-config=../../backend.hcl
terraform apply -var="alert_email=you@example.com"
```
Budget emails need no confirmation step. If an alert ever seems missing, check your spam folder.

## Prove it works

```bash
# State is in S3, not on your laptop
aws s3 ls s3://$(terraform -chdir=../bootstrap output -raw state_bucket)/foundation/

# The subnets have no route to the internet: only "local" plus the S3 prefix list
aws ec2 describe-route-tables --route-table-ids $(terraform output -raw private_route_table_id) \
  --query 'RouteTables[0].Routes[].[DestinationCidrBlock,DestinationPrefixListId,GatewayId]' --output table

# KMS round trip: encrypt with your key, then decrypt
aws kms encrypt --key-id alias/cpl-main --plaintext fileb://<(echo "hello kms") \
  --query CiphertextBlob --output text | base64 -d > /tmp/secret.bin
aws kms decrypt --ciphertext-blob fileb:///tmp/secret.bin --query Plaintext --output text | base64 -d

# Rotation is on
aws kms get-key-rotation-status --key-id alias/cpl-main

# The budget exists
aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text) \
  --query 'Budgets[].{Name:BudgetName,Limit:BudgetLimit.Amount}' --output table
```

The route table should show only `10.20.0.0/16 → local` and a `pl-xxxx` (S3 prefix list) row pointing to the endpoint.

## Clean up
Leave this module running while you work through the lab. It costs about $1/month. When you're completely done:

```bash
cd 00-foundation/foundation && terraform destroy -var="alert_email=you@example.com"
cd ../bootstrap && terraform destroy     # destroy this last, it holds everyone's state
```
The KMS key goes into a 7-day "pending deletion" state instead of disappearing immediately. That's a
safety feature: data encrypted with a deleted key is gone forever.

## Questions you should be able to answer
1. What is Terraform state, and what goes wrong if two engineers keep it locally?
2. How does state locking work with the S3 backend today, and what did teams use before Terraform 1.10?
3. Why can't the bootstrap stack use the S3 backend?
4. What makes a subnet private? How would you make one public?
5. Gateway endpoint vs interface endpoint: which services, how do they route, what do they cost?
6. Why is `enable_dns_hostnames` needed for interface endpoints with private DNS?
7. AWS-managed vs customer-managed KMS key: what extra control do you get?
8. What happens to encrypted data if the KMS key is deleted? Why is there a deletion window?
9. Why take over the default security group with `aws_default_security_group`?
