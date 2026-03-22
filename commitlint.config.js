const scopes = [
        // content_generation
        "content_generation/readme_diy",

        // emulation
        "emulation/zmu",

        // gpu_computing
        "gpu_computing/vulkan-zig",
        "gpu_computing/wheat",
        "gpu_computing/zig_tests",

        // graph_walking
        "graph_walking/wdw",

        // node_tooling
        "node_tooling/silo",

        // packaging
        "packaging/celeste_flake",
        "packaging/snowblock",

        // scraping
        "scraping/gbscraper",
        "scraping/gbscraper_old",

        // system_tooling
        "system_tooling/isod",

        // webapps
        "webapps/instanc.es",

        // repo-wide
        "repo", // root-level changes
        "ci",
        "deps", // root-level deps updates
        "release", // release-please bot
];

module.exports = {
        extends: ["@commitlint/config-conventional"],
        rules: {
                "scope-enum": [2, "always", scopes],
                "scope-empty": [2, "never"],
        },
};
