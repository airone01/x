import fs from "node:fs";
import path from "node:path";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";
import pino from "pino";

// types

interface ScraperStats {
  created: number;
  updated: number;
  skipped: number;
  rejected: number;
}

type NetworkType = "Clearnet" | "Tor" | "I2P";
type StatusType = "Online" | "Degraded" | "Offline" | "Unknown";

interface InvidiousMonitor {
  statusClass?: "success" | "warning" | "danger" | "error" | string;
}

interface InvidiousStatsData {
  metadata?: {
    users?: {
      total?: number;
    };
  };
}

interface InvidiousInstanceDetails {
  type?: string;
  api?: boolean;
  region?: string;
  monitor?: InvidiousMonitor;
  stats?: InvidiousStatsData;
  domain?: string;
  uri?: string;
}

// API returns array of tuples [string, details] or just details objects
type InvidiousResponseItem =
  | [string, InvidiousInstanceDetails]
  | InvidiousInstanceDetails;

interface ArchLinuxMirror {
  url: string;
  protocol: string;
  completion_pct: number;
  delay: number;
  country_code: string;
}
interface ArchLinuxResponse {
  version: number;
  urls: ArchLinuxMirror[];
}

// setup

const logger = pino({
  level: "info",
  transport: {
    target: "pino-pretty",
    options: {
      colorize: true,
      ignore: "pid,hostname",
      translateTime: "SYS:standard",
    },
  },
});

const OUTPUT_DIR = path.join(process.cwd(), "src", "data", "instances");

// shared utils

function writeMdx(
  software: string,
  domain: string,
  tags: string[],
  status: StatusType,
  region: string,
  network: NetworkType,
  users?: number,
  exactUrl?: string, // for support of mirrors with subdirs
): "created" | "updated" | "skipped" {
  const slug = `${software.toLowerCase()}-${domain.replace(/\./g, "-")}`;
  const filePath = path.join(OUTPUT_DIR, `${slug}.mdx`);

  const instanceData = { domain, status, region, network, users, exactUrl };
  const dataHash = JSON.stringify(instanceData);

  let pubDatetime = new Date().toISOString();
  let modDatetime: string | null = null;
  let oldDataHash = "";
  let isNewFile = true;

  if (fs.existsSync(filePath)) {
    isNewFile = false;
    const existingContent = fs.readFileSync(filePath, "utf-8");

    const pubMatch = existingContent.match(/pubDatetime:\s*(.+)/);
    if (pubMatch?.[1]) pubDatetime = pubMatch[1].trim();

    const modMatch = existingContent.match(/modDatetime:\s*(.+)/);
    if (modMatch?.[1]) modDatetime = modMatch[1].trim();

    const hashMatch = existingContent.match("");
    if (hashMatch?.[1]) oldDataHash = hashMatch[1].trim();
  }

  if (!isNewFile && oldDataHash === dataHash) {
    // nothing changed
    return "skipped";
  }

  if (!isNewFile && oldDataHash !== dataHash) {
    // something changed: update
    modDatetime = new Date().toISOString();
  }

  const urlToUse =
    exactUrl || `${network === "Clearnet" ? "https://" : "http://"}${domain}`;

  const frontmatter = [
    `---`,
    `title: "${software}: ${domain}"`,
    `slug: "${slug}"`,
    `pubDatetime: ${pubDatetime}`,
    modDatetime ? `modDatetime: ${modDatetime}` : null,
    `featured: false`,
    `draft: false`,
    `tags:`,
    ...tags.map((t) => `  - ${t}`),
    `description: "${software} ${network} mirror hosted at ${domain}. Currently ${status}."`,
    `---`,
  ]
    .filter(Boolean)
    .join("\n");

  const mdxContent = `${frontmatter}\n
import InstanceInfo from "@/components/InstanceInfo.astro";

<InstanceInfo 
  software="${software}"
  url="${urlToUse}"
  status="${status}"
  region="${region}"
  network="${network}"
  ${users !== undefined ? `users={${users}}` : ""}
/>
`.replace(/\n\n+/g, "\n\n"); // enforce clean spacing

  if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  }

  fs.writeFileSync(filePath, mdxContent, "utf-8");
  return isNewFile ? "created" : "updated";
}

// scraper modules

type ScraperFn = () => Promise<ScraperStats>;

const scrapers: Record<string, ScraperFn> = {
  invidious: async (): Promise<ScraperStats> => {
    logger.info("Fetching from api.invidious.io...");
    const API_URL =
      "https://api.invidious.io/instances.json?sort_by=type,health";

    const res = await fetch(API_URL);
    if (!res.ok) throw new Error(`API returned status: ${res.status}`);

    const data = (await res.json()) as InvidiousResponseItem[];
    logger.info(`Fetched ${data.length} total instances.`);

    const stats: ScraperStats = {
      created: 0,
      updated: 0,
      skipped: 0,
      rejected: 0,
    };

    for (const item of data) {
      let domain = "";
      let details: InvidiousInstanceDetails = {};

      if (Array.isArray(item)) {
        domain = item[0];
        details = item[1] || {};
      } else if (typeof item === "object" && item !== null) {
        domain = item.domain || item.uri || "";
        details = item;
      }

      if (!domain) {
        stats.rejected++;
        continue;
      }

      // network
      let network: NetworkType = "Clearnet";
      if (details.type === "onion" || domain.endsWith(".onion"))
        network = "Tor";
      else if (details.type === "i2p" || domain.endsWith(".i2p"))
        network = "I2P";

      // status
      let status: StatusType = "Online";
      const monitorStatus = details.monitor?.statusClass;

      if (monitorStatus === "warning") status = "Degraded";
      else if (monitorStatus === "danger" || monitorStatus === "error")
        status = "Offline";
      else status = details.api === true ? "Online" : "Unknown";

      // other metrics
      const region = details.region || "Unknown";
      const users = details.stats?.metadata?.users?.total;

      const result = writeMdx(
        "Invidious",
        domain,
        ["invidious", "youtube", "video"],
        status,
        region,
        network,
        users,
      );

      stats[result]++;
    }
    return stats;
  },

  archlinux: async (): Promise<ScraperStats> => {
    logger.info("Fetching from archlinux.org...");
    const API_URL = "https://archlinux.org/mirrors/status/json/"; //

    const res = await fetch(API_URL);
    if (!res.ok) throw new Error(`API returned status: ${res.status}`);

    const data = (await res.json()) as ArchLinuxResponse;
    const mirrors = data.urls;
    logger.info(`Fetched ${mirrors.length} total Arch Linux mirrors.`);

    const stats: ScraperStats = {
      created: 0,
      updated: 0,
      skipped: 0,
      rejected: 0,
    };

    for (const mirror of mirrors) {
      // arch mirror list includes http and rsync
      // we only process https
      if (mirror.protocol !== "https") {
        stats.rejected++;
        continue;
      }

      let domain = "";
      try {
        const urlObj = new URL(mirror.url);
        domain = urlObj.hostname;
      } catch {
        stats.rejected++;
        continue;
      }

      const network: NetworkType = "Clearnet";

      // calculate health based on completion percentage and synchronization delay
      let status: StatusType = "Online";
      if (mirror.completion_pct < 0.98 || mirror.delay > 86400) {
        status = "Degraded";
      }
      if (mirror.completion_pct < 0.8) {
        status = "Offline";
      }

      const region = mirror.country_code || "Unknown";

      const result = writeMdx(
        "archlinux",
        domain,
        ["archlinux", "linux", "package-manager", "mirror"],
        status,
        region,
        network,
        undefined,
        mirror.url,
      );

      stats[result]++;
    }
    return stats;
  },

  // future scrapers
};

async function main() {
  const argv = await yargs(hideBin(process.argv))
    .option("scrape", {
      type: "string",
      description: "Which service to scrape",
      choices: [...Object.keys(scrapers), "all"],
      default: "all",
    })
    .help().argv;

  const target = argv.scrape as string;
  const toRun = target === "all" ? Object.keys(scrapers) : [target];

  logger.info(`Starting scrape job for: ${toRun.join(", ")}`);

  for (const name of toRun) {
    try {
      const scraper = scrapers[name];
      if (!scraper) throw new Error(`Scraper ${name} not found`);

      const stats = await scraper();
      logger.info({ scraper: name, stats }, `Completed successfully`);
    } catch (err) {
      logger.error({ scraper: name, err }, `Scraper failed`);
    }
  }
}

main();
