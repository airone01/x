use clap::{Parser, Subcommand};
use comfy_table::{Cell, Table};
use serde_yaml::Value;
use std::collections::{HashMap, HashSet};
use std::fs::File;
use std::io::Read;
use std::path::PathBuf;
use wdw::{Node, Requirement, resolve_min_nodes, topo_order};

/// Simple quest walker that resolves AND/OR requirements defined in YAML.
///
/// Design goals:
/// - No external graph library used; graph/resolution implemented manually.
/// - Keep code modular and small so more algorithms can be added later.
#[derive(Parser, Debug)]
#[command(author, version, about)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Walk to a target node and compute the best path
    Walk {
        /// Target node id to resolve
        target: String,

        /// Start node (optional, not used by current algorithm)
        #[arg(long)]
        start: Option<String>,

        /// Input file containing a list of nodes
        #[arg(short, long, value_name = "FILE")]
        input: PathBuf,

        /// Comma-separated list (or repeated -s) of node property keys to show as extra columns (text only)
        #[arg(short = 's', long = "show", value_delimiter = ',', num_args = 0..)]
        show_props: Vec<String>,

        /// Algorithm to use
        #[arg(long, default_value = "min-nodes")]
        algo: String,
    },
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    match &cli.command {
        Commands::Walk {
            target,
            input,
            show_props,
            algo,
            ..
        } => {
            // read file
            let mut s = String::new();
            File::open(input)?.read_to_string(&mut s)?;
            let nodes: Vec<Node> = serde_yaml::from_str(&s)
                .map_err(|e| anyhow::anyhow!("Failed to parse YAML: {}", e))?;

            // index by id
            let mut map: HashMap<String, Node> = HashMap::new();
            for n in nodes.into_iter() {
                if map.insert(n.id.clone(), n).is_some() {
                    return Err(anyhow::anyhow!("Duplicate node id found"));
                }
            }

            if !map.contains_key(target) {
                return Err(anyhow::anyhow!("Target '{}' not found in input", target));
            }

            match algo.as_str() {
                "min-nodes" => {
                    let mut stack = Vec::new();
                    let mut visiting: HashSet<String> = HashSet::new();
                    let mut banned: HashSet<String> = HashSet::new();

                    // Pass banned into the resolver so `type: not` can populate it.
                    let chosen =
                        resolve_min_nodes(target, &map, &mut visiting, &mut stack, &mut banned)?;

                    // Remove banned nodes from the chosen set (final sanitization).
                    let chosen: HashSet<String> =
                        chosen.into_iter().filter(|c| !banned.contains(c)).collect();

                    // Determine a completion order (topological among chosen nodes)
                    let order = topo_order(&chosen, &map)?;

                    // Compute depths for each chosen node (depth = max prereq depth + 1)
                    let depths = compute_depths(&order, &map, &chosen);

                    // Render table: columns = depth, id, + show_props
                    let mut table = Table::new();
                    // header
                    let mut header = vec![Cell::from("depth"), Cell::from("id")];
                    for k in show_props {
                        header.push(Cell::from(k.as_str()));
                    }
                    table.set_header(header);

                    for id in &order {
                        if let Some(node) = map.get(id) {
                            let mut row = vec![
                                Cell::from(depths.get(id).unwrap_or(&0).to_string()),
                                Cell::from(id),
                            ];

                            for k in show_props {
                                let cell = extract_text_prop(&node.extra, k);
                                row.push(Cell::from(cell));
                            }

                            table.add_row(row);
                        }
                    }

                    println!("Algorithm: min-nodes");
                    println!("Target: {}", target);
                    println!("Banned nodes: {:?}", banned);
                    println!("Chosen nodes: {}", chosen.len());
                    println!("{}", table);
                }
                other => {
                    return Err(anyhow::anyhow!(
                        "Unknown algorithm '{}' (only 'min-nodes' implemented)",
                        other
                    ));
                }
            }
        }
    }

    Ok(())
}

/// Compute depths for nodes in `order` using direct prerequisites inside `chosen`.
fn compute_depths(
    order: &[String],
    map: &HashMap<String, Node>,
    chosen: &HashSet<String>,
) -> HashMap<String, usize> {
    let mut depths: HashMap<String, usize> = HashMap::new();
    for id in order.iter() {
        let node = map.get(id).unwrap();
        let prereqs = collect_direct_ids(&node.requirement);
        let mut d = 0usize;
        for p in prereqs.into_iter() {
            if chosen.contains(&p) {
                let pd = *depths.get(&p).unwrap_or(&0);
                if pd + 1 > d {
                    d = pd + 1;
                }
            }
        }
        depths.insert(id.clone(), d);
    }
    depths
}

fn extract_text_prop(extra: &HashMap<String, Value>, key: &str) -> String {
    match extra.get(key) {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Number(n)) => n.to_string(),
        Some(Value::Bool(b)) => b.to_string(),
        Some(other) => format!("{:?}", other),
        None => String::new(),
    }
}

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
