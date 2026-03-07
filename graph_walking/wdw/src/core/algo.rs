use std::collections::VecDeque;
use std::collections::{HashMap, HashSet};

use crate::core::types::{Node, Requirement};

/// Resolve the minimal set of nodes to satisfy `target` using a simple
/// recursive algorithm:
/// - For a requirement that is a bare node id: resolve that node's
/// own requirement recursively, then include that id.
/// - For AND: union the result sets of all children (fails if any child uses a banned id).
/// - For OR: choose the child whose result set is smallest (tie-breaker: first),
///         skipping branches that contain banned ids.
///
/// `visiting` is used to detect cycles (returns an error when a cycle exists).
/// `stack` is used for nicer cycle reporting.
/// `banned` accumulates node ids introduced by `type: not` requirements.
pub fn resolve_min_nodes(
    target: &str,
    map: &HashMap<String, Node>,
    visiting: &mut HashSet<String>,
    stack: &mut Vec<String>,
    banned: &mut HashSet<String>,
) -> anyhow::Result<HashSet<String>> {
    if visiting.contains(target) {
        stack.push(target.to_string());
        return Err(anyhow::anyhow!("Cycle detected: {}", stack.join(" -> ")));
    }

    visiting.insert(target.to_string());
    stack.push(target.to_string());

    let node = map
        .get(target)
        .ok_or_else(|| anyhow::anyhow!("Node '{}' not found", target))?;

    let mut result: HashSet<String> = HashSet::new();

    if let Some(req) = &node.requirement {
        let req_set = resolve_req_min(req, map, visiting, stack, banned)?;
        // If req_set contains a banned node, treat as unsatisfiable here (safety)
        if intersects_banned(&req_set, banned) {
            return Err(anyhow::anyhow!(
                "Requirement for '{}' depends on banned node(s): {:?}",
                target,
                req_set
                    .iter()
                    .filter(|i| banned.contains(*i))
                    .cloned()
                    .collect::<Vec<_>>()
            ));
        }
        result.extend(req_set);
    }

    // include the target itself as something to complete (if you want only prereqs,
    // remove this line)
    result.insert(target.to_string());

    stack.pop();
    visiting.remove(target);
    Ok(result)
}

fn resolve_req_min(
    req: &Requirement,
    map: &HashMap<String, Node>,
    visiting: &mut HashSet<String>,
    stack: &mut Vec<String>,
    banned: &mut HashSet<String>,
) -> anyhow::Result<HashSet<String>> {
    match req {
        Requirement::Id(id) => {
            // Resolve the node referenced by id
            resolve_min_nodes(id, map, visiting, stack, banned)
        }
        Requirement::Compound { kind, value } => {
            if kind.eq_ignore_ascii_case("and") {
                let mut acc: HashSet<String> = HashSet::new();
                for child in value.iter() {
                    let s = resolve_req_min(child, map, visiting, stack, banned)?;
                    // If any child requires a banned node, the AND cannot be satisfied.
                    if intersects_banned(&s, banned) {
                        return Err(anyhow::anyhow!(
                            "AND requirement unsatisfiable because a child ({:?}) requires banned node(s): {:?}",
                            child,
                            s.iter()
                                .filter(|i| banned.contains(*i))
                                .cloned()
                                .collect::<Vec<_>>()
                        ));
                    }
                    acc.extend(s);
                }
                Ok(acc)
            } else if kind.eq_ignore_ascii_case("or") {
                if value.is_empty() {
                    return Ok(HashSet::new());
                }

                let mut best: Option<HashSet<String>> = None;

                for child in value.iter() {
                    let banned_snapshot = banned.clone();
                    let result = resolve_req_min(child, map, visiting, stack, banned);

                    match result {
                        Ok(s) => {
                            if intersects_banned(&s, banned) {
                                *banned = banned_snapshot;
                                continue; // skip banned branch
                            }

                            if best.as_ref().map_or(true, |b| s.len() < b.len()) {
                                best = Some(s);
                            }
                        }
                        Err(_) => {
                            *banned = banned_snapshot;
                            continue; // OR shouldn't fail because one branch fails
                        }
                    }
                }

                if let Some(b) = best {
                    Ok(b)
                } else {
                    Err(anyhow::anyhow!(
                        "No viable OR branch: all options banned/invalid"
                    ))
                }
            } else if kind.eq_ignore_ascii_case("not") {
                // NOT: collect all referenced ids in the 'value' subtree and add them to banned.
                // We intentionally do not themselves contribute nodes to the requirement set.
                for child in value.iter() {
                    let mut ids: HashSet<String> = HashSet::new();
                    collect_ids_recursive(child, &mut ids);
                    for id in ids.into_iter() {
                        banned.insert(id);
                    }
                }
                Ok(HashSet::new())
            } else {
                Err(anyhow::anyhow!("Unknown requirement type: {}", kind))
            }
        }
    }
}

/// Build a topological order for the induced subgraph containing only `chosen` nodes.
/// Edges point from prerequisite -> dependent.
pub fn topo_order(
    chosen: &HashSet<String>,
    map: &HashMap<String, Node>,
) -> anyhow::Result<Vec<String>> {
    // compute immediate dependencies: for each node, list prereq ids that are in `chosen`
    let mut indeg: HashMap<String, usize> = HashMap::new();
    let mut adj: HashMap<String, Vec<String>> = HashMap::new();

    for id in chosen.iter() {
        indeg.insert(id.clone(), 0usize);
        adj.insert(id.clone(), Vec::new());
    }

    for id in chosen.iter() {
        if let Some(node) = map.get(id) {
            let prereqs = collect_direct_ids(&node.requirement);
            for p in prereqs.into_iter() {
                if chosen.contains(&p) {
                    // edge p -> id
                    adj.entry(p.clone()).or_default().push(id.clone());
                    *indeg.entry(id.clone()).or_default() += 1;
                }
            }
        }
    }

    // Kahn's algorithm
    let mut q: VecDeque<String> = indeg
        .iter()
        .filter_map(|(k, &v)| if v == 0 { Some(k.clone()) } else { None })
        .collect();

    let mut order: Vec<String> = Vec::new();
    while let Some(n) = q.pop_front() {
        order.push(n.clone());
        if let Some(neis) = adj.get(&n) {
            for m in neis.iter() {
                let e = indeg.get_mut(m).unwrap();
                *e -= 1;
                if *e == 0 {
                    q.push_back(m.clone());
                }
            }
        }
    }

    if order.len() != chosen.len() {
        // cycle among chosen nodes or missing edges; fallback: return list in arbitrary order
        let mut fallback: Vec<String> = chosen.iter().cloned().collect();
        fallback.sort();
        Ok(fallback)
    } else {
        Ok(order)
    }
}

/// Collect direct node ids referenced inside a requirement (shallow: returns all ids
/// referenced anywhere inside the requirement tree).
fn collect_direct_ids(req: &Option<Requirement>) -> HashSet<String> {
    let mut out = HashSet::new();
    if let Some(r) = req {
        collect_ids_recursive(r, &mut out);
    }
    out
}

fn collect_ids_recursive(req: &Requirement, out: &mut HashSet<String>) {
    match req {
        Requirement::Id(id) => {
            out.insert(id.clone());
        }
        Requirement::Compound { value, .. } => {
            for c in value.iter() {
                collect_ids_recursive(c, out);
            }
        }
    }
}

/// Helper: returns true if `set` contains any id in `banned`.
fn intersects_banned(set: &HashSet<String>, banned: &HashSet<String>) -> bool {
    set.iter().any(|id| banned.contains(id))
}
