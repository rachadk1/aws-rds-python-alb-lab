# Stage 06 — Application Load Balancer

[Français](../06-alb.md) | **English**

The browser sends an HTTP request to the ALB DNS name on port 80. The listener forwards it to a target group containing WebA and WebB on port 8080. The ALB uses the two public subnets in `us-east-2a` and `us-east-2b`. It connects to the EC2 instances through their private addresses. The web security group permits port 8080 from the ALB security group. Each application still queries the same private MySQL database on port 3306.

## Deploy and verify

From the repository root on `infra/06-alb`, with the stacks from stages 01 through 05 active:

```bash
bash scripts/deploy-alb.sh
bash scripts/check-alb.sh
```

If the AWS session has expired, run `aws login --region us-east-2` and retry the failed command. Deployment creates the `lab6-alb` stack containing the ALB, listener, and target group. CloudFormation outputs the public URL. The verification script waits for both targets to become `healthy`, tests the home page, and sends 20 requests. `ALB_OK` means the home page returned HTTP 200 and both EC2 instances answered through the ALB with their zone and an RDS TLS connection.

| Test | What it verifies |
|---|---|
| ALB check of `/health` on each target | Gunicorn and Flask answer without querying MySQL. |
| Public home page `/` | The browser can reach the ALB and Flask renders the courses page. |
| `/health?strict=1` through the ALB | Flask reaches RDS, negotiates TLS, and counts students. `served_by` and `az` identify the instance. |

If a target is `unhealthy`, check the `Reason` column, the Flask service, and the ALB-to-EC2 path on port 8080. If the strict route returns HTTP 503, use the [stage 05](05-python.md) tests to check the EC2-to-RDS connection.

## Try the registration form

1. Open the `http://` URL printed by the script. Check for the list of courses and the **Served by** field.
2. Register a fictional student with a unique address ending in `@example.com`. Note the instance in the confirmation message.
3. Refresh until the **Served by** field shows the other instance. It should list the same student because both servers read the same database.
4. Submit the same email address again. The form should report a duplicate. The strict health check should now report 13 students if the database started with the original 12.

The public listener uses HTTP for this exercise. Use fictional data only. AWS may charge for the ALB, usage, and public IPv4 addresses. To stop those charges after the exercise, delete the `lab6-alb` stack and wait for deletion to finish. Other lab stacks can still incur their own charges.

```bash
aws cloudformation delete-stack --stack-name lab6-alb --region us-east-2
aws cloudformation wait stack-delete-complete --stack-name lab6-alb --region us-east-2
```

## GitHub

After the tests pass, push `infra/06-alb` and open a PR with **base `develop`** and **compare `infra/06-alb`**. Record both AZs and the response count per server in the PR.
