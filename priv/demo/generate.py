import json, os, sys
root = sys.argv[1]
SECRET = {"4dabf18193072939515e22adb298388d": "1b47061264138c4ac30d75fd1eb44270", "ciphertext": "v1:demo"}

def stack(project, st, extra_tasks):
    p = f"urn:pulumi:{st}::{project}::"
    U = lambda t, n, parent=None: (p + (f"{parent}${t}" if parent else t) + "::" + n)
    stack_urn = U("pulumi:pulumi:Stack", f"{project}-{st}")
    prov = U("pulumi:providers:aws", "default_6_50_0")
    vpc_t = "awsx:ec2:Vpc"
    vpc = U(vpc_t, "main")
    res = [
        dict(urn=stack_urn, custom=False, type="pulumi:pulumi:Stack", outputs={"url": f"https://{st}.example.com"}),
        dict(urn=prov, custom=True, id="prov", type="pulumi:providers:aws", inputs={"region": "us-east-1"}, outputs={"region": "us-east-1"}),
        dict(urn=vpc, custom=False, type=vpc_t, parent=stack_urn),
    ]
    def add(t, n, parent, deps=(), id_=None, outputs=None, protect=False, ptype=None):
        urn = U(t, n, ptype)
        res.append(dict(urn=urn, custom=True, id=id_ or f"{n}-{st}", type=t, parent=parent, dependencies=list(deps),
                        provider=prov + "::prov", inputs={"name": n}, outputs=outputs or {"arn": f"arn:aws:demo:::{n}-{st}"}, protect=protect))
        return urn
    v = add("aws:ec2/vpc:Vpc", "main", vpc, ptype=vpc_t, id_="vpc-0a1b2c")
    subs = [add("aws:ec2/subnet:Subnet", f"private-{i}", vpc, [v], ptype=vpc_t, id_=f"subnet-0{i}") for i in "ab"]
    pub = add("aws:ec2/subnet:Subnet", "public-a", vpc, [v], ptype=vpc_t, id_="subnet-0p")
    sg = add("aws:ec2/securityGroup:SecurityGroup", "app", stack_urn, [v])
    db_sg = add("aws:ec2/securityGroup:SecurityGroup", "db", stack_urn, [v, sg])
    dbsub = add("aws:rds/subnetGroup:SubnetGroup", "db", stack_urn, subs)
    db = add("aws:rds/instance:Instance", "postgres", stack_urn, [dbsub, db_sg], protect=True,
             outputs={"endpoint": f"postgres-{st}.abc.us-east-1.rds.amazonaws.com", "password": SECRET})
    bucket = add("aws:s3/bucketV2:BucketV2", "assets", stack_urn, protect=True)
    add("aws:s3/bucketPolicy:BucketPolicy", "assets", stack_urn, [bucket])
    role = add("aws:iam/role:Role", "task", stack_urn)
    add("aws:iam/rolePolicyAttachment:RolePolicyAttachment", "task-s3", stack_urn, [role, bucket])
    cluster = add("aws:ecs/cluster:Cluster", "app", stack_urn)
    lb = add("aws:lb/loadBalancer:LoadBalancer", "web", stack_urn, [pub, sg])
    tg = add("aws:lb/targetGroup:TargetGroup", "web", stack_urn, [v])
    add("aws:lb/listener:Listener", "https", stack_urn, [lb, tg])
    td = add("aws:ecs/taskDefinition:TaskDefinition", "api", stack_urn, [role, db])
    add("aws:ecs/service:Service", "api", stack_urn, [cluster, td, tg] + subs)
    for t in extra_tasks:
        tdw = add("aws:ecs/taskDefinition:TaskDefinition", t, stack_urn, [role, db])
        add("aws:ecs/service:Service", t, stack_urn, [cluster, tdw] + subs)
    add("aws:cloudwatch/logGroup:LogGroup", "api", stack_urn)
    return res

def write(project, st, extra, updates):
    res = stack(project, st, extra)
    d = os.path.join(root, ".pulumi/stacks", project); os.makedirs(d, exist_ok=True)
    cp = {"version": 3, "checkpoint": {"stack": f"organization/{project}/{st}", "latest": {
        "manifest": {"time": updates[0][0] + "T12:00:00.000Z", "magic": "demo", "version": "v3.200.0"},
        "secrets_providers": {"type": "passphrase"}, "resources": res}}}
    json.dump(cp, open(os.path.join(d, f"{st}.json"), "w"), indent=1)
    h = os.path.join(root, ".pulumi/history", project, st); os.makedirs(h, exist_ok=True)
    import datetime
    for i, (day, result, msg, ch) in enumerate(updates):
        t = int(datetime.datetime.fromisoformat(day + "T12:00:00+00:00").timestamp())
        json.dump({"kind": "update", "startTime": t, "endTime": t + 40 + 7 * i, "message": msg, "result": result,
                   "version": len(updates) - i, "resourceChanges": ch},
                  open(os.path.join(h, f"{st}-{t}000000000.history.json"), "w"))

write("webapp", "dev", ["worker"], [
    ("2026-11-21", "succeeded", "Add worker service", {"create": 2, "same": 24}),
    ("2026-11-18", "failed", "Bump postgres to 17", {"update": 1, "same": 25}),
    ("2026-11-12", "succeeded", "Add HTTPS listener", {"create": 1, "same": 23}),
    ("2026-11-03", "succeeded", "Initial deploy", {"create": 24})])
write("webapp", "prod", [], [
    ("2026-11-19", "succeeded", "Release 1.4", {"update": 2, "same": 22}),
    ("2026-11-01", "succeeded", "Initial deploy", {"create": 24})])
write("platform", "shared", [], [("2026-10-28", "succeeded", "Shared network", {"create": 24})])
os.makedirs(os.path.join(root, ".pulumi"), exist_ok=True)
open(os.path.join(root, ".pulumi/meta.yaml"), "w").write("version: 1\n")
