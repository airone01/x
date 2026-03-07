<script lang="ts">
	import "../app.css";
	let { children } = $props();

	import { Xterm, XtermAddon } from "@battlefieldduck/xterm-svelte";
	import type {
		ITerminalOptions,
		ITerminalInitOnlyOptions,
		Terminal,
	} from "@battlefieldduck/xterm-svelte";
	import { WebContainer, type WebContainerProcess } from "@webcontainer/api";

	let terminal = $state<Terminal>();

	let options: ITerminalOptions & ITerminalInitOnlyOptions = {
		fontFamily: "JetbrainsMono Nerd Font",
	};

	let input: WritableStreamDefaultWriter<string> | undefined;

	/**
	 * Starts the main shell process
	 *
	 * @param terminal Terminal instance
	 * @returns Shell process
	 */
	async function startShell(
		terminal: Terminal,
		webcontainerInstance: WebContainer,
	): Promise<WebContainerProcess> {
		const shellProcess = await webcontainerInstance.spawn("jsh", {
			terminal: {
				cols: terminal.cols,
				rows: terminal.rows,
			},
		});
		shellProcess.output.pipeTo(
			new WritableStream({
				write(data) {
					terminal.write(data);
				},
			}),
		);
		input = shellProcess.input.getWriter();

		return shellProcess;
	}

	async function onLoad() {
		console.log("Child component has loaded");

		// FitAddon Usage
		const fitAddon = new (await XtermAddon.FitAddon()).FitAddon();
		terminal?.loadAddon(fitAddon);
		fitAddon.fit();

		terminal?.write(
			"Hi!\n\nYour container is loading...\nIf nothing shows up, try refreshing the page.\n",
		);
		let webcontainerInstance = await WebContainer.boot();
		terminal?.clear();

		const shellProcess = await startShell(terminal!, webcontainerInstance);
	}

	function onData(data: string) {
		if (input) input.write(data);
		if (!input) console.error("No input stream");
	}
</script>

{@render children()}

<Xterm bind:terminal {options} {onLoad} {onData} class="h-screen" />
