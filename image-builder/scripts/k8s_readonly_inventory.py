#!/usr/bin/env python3
"""
Read-only Kubernetes inventory for a single current context.
Output is JSON suitable for automation / AI consumption; no kubeconfig secrets embedded.
Extend by adding keys under snapshot["sections"] or new top-level keys (bump schema_version).
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone


SCHEMA_VERSION = 1


def kubectl_json(args: list[str]) -> dict:
    cmd = ["kubectl", *args]
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.PIPE, text=True)
    except FileNotFoundError:
        raise SystemExit("kubectl not found in PATH") from None
    except subprocess.CalledProcessError as e:
        err = (e.stderr or "").strip() or e.stdout.strip() or str(e)
        raise SystemExit(f"kubectl failed ({' '.join(cmd)}): {err}") from e
    if not out.strip():
        return {}
    return json.loads(out)


def kubectl_text(args: list[str]) -> str:
    cmd = ["kubectl", *args]
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.PIPE, text=True)
    except FileNotFoundError:
        raise SystemExit("kubectl not found in PATH") from None
    except subprocess.CalledProcessError as e:
        err = (e.stderr or "").strip() or str(e)
        raise SystemExit(f"kubectl failed ({' '.join(cmd)}): {err}") from e
    return out.strip()


def slim_namespace(item: dict) -> dict:
    meta = item.get("metadata") or {}
    status = item.get("status") or {}
    return {
        "name": meta.get("name"),
        "phase": status.get("phase"),
    }


def slim_ingress(item: dict) -> dict:
    meta = item.get("metadata") or {}
    spec = item.get("spec") or {}
    status = item.get("status") or {}
    rules = spec.get("rules") or []
    hosts: list[str] = []
    for rule in rules:
        h = rule.get("host")
        if h:
            hosts.append(h)
        for p in rule.get("http", {}).get("paths") or []:
            # path-level host usually inherits rule host
            pass
    tls_hosts: list[str] = []
    for t in spec.get("tls") or []:
        for h in t.get("hosts") or []:
            if h not in tls_hosts:
                tls_hosts.append(h)
    ing_class = spec.get("ingressClassName")
    if ing_class is None and "kubernetes.io/ingress.class" in (meta.get("annotations") or {}):
        ing_class = meta["annotations"]["kubernetes.io/ingress.class"]
    return {
        "namespace": meta.get("namespace"),
        "name": meta.get("name"),
        "ingress_class": ing_class,
        "hosts": hosts,
        "tls_hosts": tls_hosts,
        "load_balancer": status.get("loadBalancer", {}).get("ingress"),
    }


def build_snapshot(namespace: str | None) -> dict:
    current_context = kubectl_text(["config", "current-context"])
    api_server = kubectl_text(
        ["config", "view", "--minify", "--output", "jsonpath={.clusters[0].cluster.server}"]
    )

    version_payload: dict = {}
    try:
        version_payload = kubectl_json(["version", "-o", "json"])
    except SystemExit:
        version_payload = {}

    server_ver = (version_payload.get("serverVersion") or {}) if isinstance(version_payload, dict) else {}

    ns_args = ["get", "ns", "-o", "json"]
    ns_raw = kubectl_json(ns_args)
    namespaces = [slim_namespace(i) for i in ns_raw.get("items") or []]

    ing_args = ["get", "ingress", "-o", "json"]
    if namespace:
        ing_args[1:1] = ["-n", namespace]
    else:
        ing_args[1:1] = ["-A"]

    ing_raw = kubectl_json(ing_args)
    ingresses = [slim_ingress(i) for i in ing_raw.get("items") or []]

    return {
        "schema_version": SCHEMA_VERSION,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "cluster": {
            "current_context": current_context,
            "api_server": api_server,
            "server_version": {
                "git_version": server_ver.get("gitVersion"),
                "platform": server_ver.get("platform"),
            },
        },
        "filter": {"namespace": namespace} if namespace else {"namespace": None},
        "namespaces": namespaces,
        "ingresses": ingresses,
        "sections": {},
    }


def main() -> None:
    p = argparse.ArgumentParser(description="Emit read-only Kubernetes inventory as JSON.")
    p.add_argument(
        "-o",
        "--output",
        default="-",
        help='Write JSON to this path, or "-" for stdout (default: -)',
    )
    p.add_argument(
        "-n",
        "--namespace",
        default=None,
        help="If set, restrict ingress listing to this namespace (namespaces list is still cluster-wide).",
    )
    args = p.parse_args()

    snapshot = build_snapshot(args.namespace)
    text = json.dumps(snapshot, indent=2, ensure_ascii=False) + "\n"

    if args.output == "-":
        sys.stdout.write(text)
    else:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(text)


if __name__ == "__main__":
    main()
