# Module 1: GitHub Actions → AWS with OIDC (no access keys)

Resume bullet: *"Modernized CI/CD authentication … by implementing OpenID Connect (OIDC) federation …
eliminating long-lived AWS access keys."*

## The problem
The old way for a pipeline to deploy to AWS was to create an IAM user, generate an access key
(`AKIA…`), and paste it into the repo's secrets. That key:
- never expires unless someone rotates it,
- works from anywhere, so if it leaks (logs, a forked workflow, a laptop), an attacker can use it for months,
- is shared by everything that can read the secret,
- multiplies: 14 repos means 14 keys to rotate and audit.

## The fix: federation
Instead of storing a secret, the pipeline proves **who it is** and gets credentials that expire within an hour.

```
GitHub Actions job                  GitHub OIDC provider             AWS STS / IAM
       |  1. "give me a token"  -->         |                                |
       |  <-- 2. signed JWT (iss, aud, sub=repo:owner/repo:ref:refs/heads/main)
       |  3. AssumeRoleWithWebIdentity(role, JWT)  ------------------------->  |
       |                                     4. check signature with GitHub's public keys,
       |                                        check aud + sub against the role's trust policy
       |  <---------------------------------------- 5. temporary credentials (ASIA…, 1h)
```

- **OIDC (OpenID Connect)** is an identity layer on top of OAuth 2.0. The identity provider (here GitHub)
  issues a signed **JWT** describing the caller. Anyone can verify it with the provider's public keys
  (published at `https://token.actions.githubusercontent.com/.well-known/jwks`).
- **`aws_iam_openid_connect_provider`** tells your AWS account to trust JWTs from that issuer.
- **The role's trust policy** decides which tokens are good enough. Two conditions matter:
  - `aud` (audience) must be `sts.amazonaws.com`, meaning the token was minted for AWS and not reused from elsewhere.
  - `sub` (subject) must be `repo:SuyashKadam/cloud-platform-lab:ref:refs/heads/main`. Only this repo, only the main branch.
    Forget this condition and *any* GitHub repo in the world could assume your role. That's the classic misconfiguration.
- **The role's permission policy** decides what the job can do. Here it's deliberately tiny (least privilege).
- **STS** returns credentials starting with `ASIA` (temporary) instead of `AKIA` (long-lived), plus a session token.

`permissions: id-token: write` in the workflow is what lets the job request the JWT at all.

## Run it

```bash
cd 01-github-oidc/terraform
terraform init -backend-config=../../backend.hcl
terraform apply
terraform output role_arn
```

> If you get `EntityAlreadyExists` for the OIDC provider, your account already has one for GitHub.
> Import it instead of creating it:
> `terraform import aws_iam_openid_connect_provider.github arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com`
> then run `terraform apply` again.

Then in GitHub: **Settings → Secrets and variables → Actions → Variables tab → New repository variable**:

| Name | Value |
|---|---|
| `AWS_ROLE_ARN` | the `role_arn` output |
| `AWS_REGION` | `us-east-1` |

These are *variables*, not secrets. A role ARN isn't sensitive, because without a valid GitHub token it's useless.
That's the point of this module.

## Prove it works

**1. The happy path.** Go to **Actions → oidc-demo → Run workflow** on `main`. In the log:
- the token claims show `"sub": "repo:SuyashKadam/cloud-platform-lab:ref:refs/heads/main"`
- `get-caller-identity` shows `assumed-role/cpl-github-actions/gh-<run id>`
- the VPC from Module 0 is listed
- `aws s3 ls` is **denied**, because the role can only do what its policy allows
- the access key starts with `ASIA`, so the credentials are temporary

**2. The trust policy actually blocks other branches.**
```bash
git checkout -b oidc-test && git push -u origin oidc-test
```
Run the workflow again, choosing branch `oidc-test`. The claims step shows `sub: …:ref:refs/heads/oidc-test`,
and the AWS step fails with `Not authorized to perform sts:AssumeRoleWithWebIdentity`. Same repo, same workflow,
different branch, so no access. Delete the branch afterwards: `git push origin --delete oidc-test`.

**3. Find the login in CloudTrail.**
```bash
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 5 --query 'Events[].{Time:EventTime,User:Username}' --output table
```
Every pipeline login is recorded with the GitHub identity it came from. That's the "audit readiness" part of the bullet.

## Clean up
Free to keep. To remove: `terraform destroy` in `01-github-oidc/terraform`, then delete the two repo variables.

## Scaling this to "14 repositories"
At DXC scale you wouldn't hand-write 14 roles. Typical patterns:
- One role per repo/environment, created by a Terraform module looped over a list of repos.
- `StringLike` on `sub` for patterns, for example `repo:org/*:environment:prod` combined with GitHub Environments and required reviewers.
- Separate roles for `plan` (read-only, any branch / pull requests) and `apply` (write, `main` only).

## Questions you should be able to answer
1. Why are long-lived access keys in CI a risk? Name three concrete ways they leak.
2. Walk through what happens between `configure-aws-credentials` starting and the first AWS call succeeding.
3. What are `iss`, `aud` and `sub` in the JWT, and which ones does the trust policy check?
4. What happens if you leave out the `sub` condition?
5. Why does the workflow need `permissions: id-token: write`?
6. How do you tell temporary credentials from long-lived ones?
7. How would you give pull requests read-only access but only `main` the right to deploy?
8. Where would you look to audit which pipeline did what in AWS?
