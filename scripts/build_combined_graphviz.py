#!/usr/bin/env python3
"""
Combine all 6 OpenPlanter knowledge graphs into a unified Graphviz visualization.
Cross-graph entity bridges are inferred via fuzzy label match.
"""
import json
import os
import re
from collections import defaultdict
from pathlib import Path

OP = Path('/home/gwohl/builds/OpenPlanter')
OUT = Path('/home/gwohl/code/uaps/run/reports/graphviz')
OUT.mkdir(parents=True, exist_ok=True)

GRAPHS = [
    ('six_mile_runs', OP / 'knowledge_graph.json'),
    ('halterjl1',     OP / 'halterjl1_knowledge_graph.json'),
    ('zolon',         OP / 'zolon_knowledge_graph.json'),
    ('aaro',          OP / 'aaro_knowledge_graph.json'),
    ('trump_uap',     OP / 'trump_uap_directive_knowledge_graph.json'),
    ('dow_proc',      OP / 'dow_website_procurement_knowledge_graph.json'),
]

CLUSTER_COLORS = {
    'six_mile_runs': '#9F2B68',
    'halterjl1':     '#1F77B4',
    'zolon':         '#FF7F0E',
    'aaro':          '#2CA02C',
    'trump_uap':     '#D62728',
    'dow_proc':      '#8C564B',
}

CLUSTER_LABELS = {
    'six_mile_runs': '6 Mile Runs / BEvans',
    'halterjl1':     'HalterJL1 / DoD365J',
    'zolon':         'Zolon Tech (Prime)',
    'aaro':          'AARO / OUSD(R&E)',
    'trump_uap':     'Trump Directive / NDAA',
    'dow_proc':      'DoW Website Procurement',
}


def normalize_label(s):
    if not s:
        return ''
    s = str(s).lower().strip()
    s = re.sub(r'[^a-z0-9]+', ' ', s)
    s = re.sub(r'\s+', ' ', s).strip()
    # collapse legal-entity boilerplate
    s = re.sub(r'\b(inc|llc|lc|ltd|corp|company|co|the)\b', '', s)
    s = re.sub(r'\s+', ' ', s).strip()
    return s


def extract_nodes_edges(name, path):
    if not path.exists():
        return [], [], {}
    d = json.load(open(path))
    # support nested {graph:{nodes,edges}} as well
    if 'graph' in d and isinstance(d['graph'], dict):
        d = d['graph']

    raw_nodes = d.get('nodes', [])
    raw_edges = d.get('edges', [])

    nodes = []
    if isinstance(raw_nodes, dict):
        # nested per-category
        for cat, items in raw_nodes.items():
            if isinstance(items, list):
                for n in items:
                    if isinstance(n, dict):
                        n = dict(n)
                        n.setdefault('type', cat[:-1] if cat.endswith('s') else cat)
                        nodes.append(n)
    elif isinstance(raw_nodes, list):
        nodes = raw_nodes

    edges = []
    if isinstance(raw_edges, dict):
        for cat, items in raw_edges.items():
            if isinstance(items, list):
                for e in items:
                    if isinstance(e, dict):
                        edges.append(e)
    elif isinstance(raw_edges, list):
        edges = raw_edges

    # uniformize node IDs and labels
    norm_nodes = []
    label_to_id = {}
    for n in nodes:
        nid = n.get('id') or n.get('node_id') or n.get('name')
        if not nid:
            continue
        label = n.get('label') or n.get('name') or n.get('id') or ''
        ntype = n.get('type') or n.get('category') or 'entity'
        norm_id = f"{name}__{nid}"
        norm_nodes.append({
            'id': norm_id,
            'orig_id': str(nid),
            'label': str(label),
            'type': str(ntype),
            'cluster': name,
            'norm_label': normalize_label(label),
            'extra': {k: v for k, v in n.items() if k not in ('id', 'label', 'type', 'name')}
        })
        label_to_id[str(nid)] = norm_id

    norm_edges = []
    for e in edges:
        src = e.get('source') or e.get('from') or e.get('src') or e.get('s')
        tgt = e.get('target') or e.get('to')   or e.get('dst') or e.get('t')
        if not src or not tgt:
            continue
        rel = e.get('relationship') or e.get('label') or e.get('type') or e.get('rel') or ''
        norm_edges.append({
            'src': f"{name}__{src}",
            'tgt': f"{name}__{tgt}",
            'rel': str(rel),
            'cluster': name,
        })
    return norm_nodes, norm_edges, label_to_id


def build():
    all_nodes = []
    all_edges = []
    by_label = defaultdict(list)  # norm_label -> [node]

    for name, path in GRAPHS:
        ns, es, _ = extract_nodes_edges(name, path)
        all_nodes.extend(ns)
        all_edges.extend(es)
        for n in ns:
            if n['norm_label']:
                by_label[n['norm_label']].append(n)

    # cross-cluster bridges: same normalized label appearing in 2+ clusters
    bridge_edges = []
    for lbl, nodes in by_label.items():
        clusters = set(n['cluster'] for n in nodes)
        if len(clusters) >= 2 and len(lbl) >= 3:
            # connect each pair of nodes with the SAME label across clusters
            for i, a in enumerate(nodes):
                for b in nodes[i+1:]:
                    if a['cluster'] != b['cluster']:
                        bridge_edges.append({
                            'src': a['id'],
                            'tgt': b['id'],
                            'rel': '≡ same entity',
                            'cluster': '__bridge__',
                        })

    # render DOT
    out = []
    out.append('digraph UAPS_combined {')
    out.append('  rankdir=LR;')
    out.append('  graph [bgcolor="#FAFAFA", overlap=false, splines=true, fontname="Helvetica", labelloc=t, label="PURSUE / war.gov/ufo Forensic Knowledge Graph (combined, 6 sources)\\n2026-05-09"];')
    out.append('  node  [shape=box, style="filled,rounded", fontname="Helvetica", fontsize=10];')
    out.append('  edge  [fontname="Helvetica", fontsize=8, color="#666666", arrowsize=0.6];')

    # subgraph clusters
    nodes_by_cluster = defaultdict(list)
    for n in all_nodes:
        nodes_by_cluster[n['cluster']].append(n)

    for cluster_name, _ in GRAPHS:
        c_nodes = nodes_by_cluster.get(cluster_name, [])
        if not c_nodes:
            continue
        color = CLUSTER_COLORS.get(cluster_name, '#888888')
        clabel = CLUSTER_LABELS.get(cluster_name, cluster_name)
        out.append(f'  subgraph cluster_{cluster_name} {{')
        out.append(f'    label="{clabel}";')
        out.append(f'    color="{color}";')
        out.append(f'    style="rounded,filled";')
        out.append(f'    fillcolor="{color}33";')
        out.append(f'    fontname="Helvetica-Bold";')
        out.append(f'    fontsize=11;')
        for n in c_nodes:
            label = n['label'].replace('"', "'").strip()
            if not label:
                label = n['orig_id']
            # truncate long labels
            if len(label) > 60:
                label = label[:57] + '…'
            t = n['type'].lower() if n['type'] else ''
            shape = 'box'
            fill = color + '88'
            if 'person' in t or 'people' in t:
                shape = 'ellipse'
            elif 'org' in t or 'company' in t or 'agency' in t:
                shape = 'box'
            elif 'event' in t:
                shape = 'parallelogram'
            elif 'program' in t or 'contract' in t:
                shape = 'note'
            elif 'document' in t or 'record' in t or 'pub' in t:
                shape = 'folder'
            elif 'committee' in t or 'panel' in t:
                shape = 'octagon'
            out.append(f'    "{n["id"]}" [label="{label}\\n[{n["type"]}]", shape={shape}, fillcolor="{fill}"];')
        out.append('  }')

    # intra-cluster edges
    out.append('')
    out.append('  // intra-cluster edges')
    for e in all_edges:
        rel = e['rel'].replace('"', "'")
        if len(rel) > 30:
            rel = rel[:27] + '…'
        cluster = e['cluster']
        col = CLUSTER_COLORS.get(cluster, '#666666')
        out.append(f'  "{e["src"]}" -> "{e["tgt"]}" [label="{rel}", color="{col}"];')

    # cross-cluster bridges
    out.append('')
    out.append('  // cross-cluster bridges (≡ same entity, fuzzy matched)')
    seen_pairs = set()
    for e in bridge_edges:
        key = tuple(sorted([e['src'], e['tgt']]))
        if key in seen_pairs:
            continue
        seen_pairs.add(key)
        out.append(f'  "{e["src"]}" -> "{e["tgt"]}" [label="{e["rel"]}", style=dashed, color="#444444", penwidth=2, dir=none, constraint=false];')

    out.append('}')
    dot = '\n'.join(out)

    (OUT / 'combined.dot').write_text(dot)
    json_summary = {
        'total_nodes': len(all_nodes),
        'total_edges': len(all_edges),
        'cross_cluster_bridges': len(seen_pairs),
        'cluster_sizes': {c: len(ns) for c, ns in nodes_by_cluster.items()},
        'sources': {name: str(path) for name, path in GRAPHS},
        'bridge_pairs': sorted([f'{a} <-> {b}' for a, b in seen_pairs]),
    }
    (OUT / 'combined.json').write_text(json.dumps(json_summary, indent=2))
    print(f'Wrote combined.dot with {len(all_nodes)} nodes, {len(all_edges)} edges, {len(seen_pairs)} bridges')
    print(f'Cluster sizes: {json_summary["cluster_sizes"]}')
    return dot


if __name__ == '__main__':
    build()
