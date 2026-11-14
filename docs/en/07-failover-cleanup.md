# Stage 07 — Failover, evidence, and cleanup

[Français](../07-failover-cleanup.md) | **English**

## Simulate a failure on the ALB-to-WebA path

From the `ops/07-failover-cleanup` branch:

```bash
bash scripts/test-alb-failover.sh
```

The script checks that both targets answer. It then updates `lab6-alb` through CloudFormation to register WebA on port 8081 instead of 8080. Flask keeps listening on 8080 and the web security group allows the ALB on 8080. The ALB therefore loses access to WebA while the Flask process remains running. WebB stays on port 8080.

| Moment | WebA | WebB | Observed behavior |
|---|---|---|---|
| Before | 8080, `healthy` | 8080, `healthy` | Both instances answer. |
| During | 8081, `unhealthy` | 8080, `healthy` | After detection, WebB handles all 10 requests. |
| After | 8080, `healthy` | 8080, `healthy` | Both answer again. The script prints `FAILOVER_OK`. |

Transient failures are possible while changes propagate or health checks detect the issue. The test measures requests after the state changes. It demonstrates continuity with one healthy web target. RDS remains a Single-AZ instance.

If your terminal closes during the exercise or your AWS session expires, restore the normal setup from Git Bash.

```bash
bash scripts/deploy-alb.sh
bash scripts/check-alb.sh
```

For your portfolio, record both zones, target states, the number of responses served by WebB during the failure, and the result after recovery. Mask account identifiers and the temporary URL in any shared screenshots. You can save raw outputs in `local/`, which Git ignores.

## Clean up AWS resources

After testing and collecting your evidence, preview the affected stacks in the current account and the `us-east-2` Region.

```bash
bash scripts/cleanup-lab.sh
```

The following command starts deletion. It erases the `lab6-mysql` data without a final snapshot and waits for each stack. The existing SSH key `1st-web-server` is reused by the lab and remains available.

```bash
bash scripts/cleanup-lab.sh --delete
```

Stack deletion order:

1. `lab6-alb` and `lab6-python` remove the public entry point and installation associations.
2. `lab6-ec2` removes the instances and lab volumes. `lab6-sql-bootstrap` then removes its IAM profiles, associations, and application secret.
3. `lab6-rds` removes the MySQL instance and its automated backups.
4. `lab6-security` and then `lab6-network` remove the security groups, NAT Gateway, Elastic IP, and VPC.

The script prints `CLEANUP_OK` after processing the stacks and checking for the absence of the `lab6-mysql` instance, automated backups, and manual snapshots. It reports any existing manual snapshot for review. If a stack fails to delete, the script stops and prints available deletion failure events. After addressing the issue, run the same command again.

## GitHub

Push the branch and open a PR with `develop` as its base. Add the results before, during, and after the test, then the cleanup result if you ran it.
