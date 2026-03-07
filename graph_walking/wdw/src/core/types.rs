use serde::de::Error as DeError;
use serde::{Deserialize, Deserializer};
use serde_yaml::Value;
use std::collections::HashMap;

/// Represents a dependency requirement. Supports shorthand YAML forms:
/// - `requirement: - A - B` or `requirement_and:` → AND
/// - `requirement_or:` → OR
/// - `requirement: !A` → NOT
#[derive(Debug, Clone)]
pub enum Requirement {
    Id(String),
    Compound {
        kind: String,
        value: Vec<Requirement>,
    },
}

impl Requirement {
    fn from_yaml_value(v: Value) -> Result<Self, String> {
        match v {
            Value::String(s) => {
                // "!id" shorthand -> not
                if let Some(rest) = s.strip_prefix('!') {
                    Ok(Requirement::Compound {
                        kind: "not".to_string(),
                        value: vec![Requirement::Id(rest.to_string())],
                    })
                } else {
                    Ok(Requirement::Id(s))
                }
            }

            Value::Sequence(seq) => {
                // Top-level sequence -> implicit AND of items
                let mut items = Vec::with_capacity(seq.len());
                for item in seq {
                    items.push(Requirement::from_yaml_value(item)?);
                }
                Ok(Requirement::Compound {
                    kind: "and".to_string(),
                    value: items,
                })
            }

            Value::Mapping(map) => {
                let type_key = Value::String("type".into());
                let value_key = Value::String("value".into());

                // 1) Explicit { type: "...", value: ... } shape (preferred)
                if let Some(tval) = map.get(&type_key) {
                    let kind = match tval {
                        Value::String(s) => s.clone(),
                        other => {
                            return Err(format!("Invalid requirement 'type' value: {:?}", other));
                        }
                    };

                    let val_field = map
                        .get(&value_key)
                        .cloned()
                        .unwrap_or(Value::Sequence(vec![]));
                    let mut items = Vec::new();
                    match val_field {
                        Value::Sequence(seq) => {
                            for item in seq {
                                items.push(Requirement::from_yaml_value(item)?);
                            }
                        }
                        other => items.push(Requirement::from_yaml_value(other)?),
                    }

                    return Ok(Requirement::Compound { kind, value: items });
                }

                // 2) Shorthand where the mapping key itself is "and", "or", or "not":
                //    e.g. { or: [a, b] } or { not: a } or { AND: [a, b] }
                for (k, v) in map.iter() {
                    if let Value::String(key_s) = k {
                        let kl = key_s.trim().to_ascii_lowercase();
                        if kl == "and" || kl == "or" || kl == "not" {
                            let mut items = Vec::new();
                            match v {
                                Value::Sequence(seq) => {
                                    // clone items to consume; recursion will own the Value
                                    for item in seq.clone() {
                                        items.push(Requirement::from_yaml_value(item)?);
                                    }
                                }
                                other => {
                                    // single item under the key
                                    items.push(Requirement::from_yaml_value(other.clone())?);
                                }
                            }
                            return Ok(Requirement::Compound {
                                kind: kl,
                                value: items,
                            });
                        }
                    }
                }

                // 3) If there's a "value" key but no "type", default to AND
                if let Some(val_field) = map.get(&value_key) {
                    let mut items = Vec::new();
                    match val_field.clone() {
                        Value::Sequence(seq) => {
                            for item in seq {
                                items.push(Requirement::from_yaml_value(item)?);
                            }
                        }
                        other => items.push(Requirement::from_yaml_value(other)?),
                    }
                    return Ok(Requirement::Compound {
                        kind: "and".into(),
                        value: items,
                    });
                }

                // 4) Fallback: stringify mapping as an Id (defensive)
                let s = serde_yaml::to_string(&Value::Mapping(map))
                    .unwrap_or_else(|_| "<invalid>".into());
                Ok(Requirement::Id(s.trim().to_string()))
            }

            Value::Null => Err("Null requirement is not valid".into()),

            other => {
                // numbers & bools -> stringify
                let s = serde_yaml::to_string(&other).unwrap_or_else(|_| format!("{:?}", other));
                Ok(Requirement::Id(s.trim().to_string()))
            }
        }
    }
}

impl<'de> Deserialize<'de> for Requirement {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let v = Value::deserialize(deserializer).map_err(DeError::custom)?;
        Requirement::from_yaml_value(v).map_err(DeError::custom)
    }
}

#[derive(Debug, Clone)]
pub struct Node {
    pub id: String,
    pub requirement: Option<Requirement>,
    pub extra: HashMap<String, Value>,
}

impl<'de> Deserialize<'de> for Node {
    fn deserialize<D>(deserializer: D) -> Result<Node, D::Error>
    where
        D: Deserializer<'de>,
    {
        let mapping = serde_yaml::Mapping::deserialize(deserializer).map_err(DeError::custom)?;
        let mut raw_map: HashMap<String, Value> = HashMap::new();

        for (k, v) in mapping {
            let key = match k {
                Value::String(s) => s,
                other => serde_yaml::to_string(&other).unwrap_or_else(|_| format!("{:?}", other)),
            };
            raw_map.insert(key.trim().to_string(), v);
        }

        let id_value = raw_map
            .remove("id")
            .ok_or_else(|| DeError::custom("Node is missing required 'id' field"))?;
        let id = match id_value {
            Value::String(s) => s,
            other => serde_yaml::to_string(&other)
                .unwrap_or_else(|_| format!("{:?}", other))
                .trim()
                .to_string(),
        };

        // Handle requirement forms
        let mut requirement = None;
        if let Some(rv) = raw_map.remove("requirement") {
            requirement = Some(Requirement::from_yaml_value(rv).map_err(DeError::custom)?);
        } else if let Some(rv) = raw_map.remove("requirement_and") {
            let parsed = Requirement::from_yaml_value(rv).map_err(DeError::custom)?;
            match parsed {
                Requirement::Compound { kind, value } if kind.eq_ignore_ascii_case("and") => {
                    requirement = Some(Requirement::Compound { kind, value })
                }
                other => {
                    requirement = Some(Requirement::Compound {
                        kind: "and".into(),
                        value: vec![other],
                    })
                }
            }
        } else if let Some(rv) = raw_map.remove("requirement_or") {
            let parsed = Requirement::from_yaml_value(rv).map_err(DeError::custom)?;
            match parsed {
                Requirement::Compound { kind, value } if kind.eq_ignore_ascii_case("or") => {
                    requirement = Some(Requirement::Compound { kind, value })
                }
                other => {
                    requirement = Some(Requirement::Compound {
                        kind: "or".into(),
                        value: vec![other],
                    })
                }
            }
        }

        Ok(Node {
            id,
            requirement,
            extra: raw_map,
        })
    }
}
