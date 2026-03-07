import './style.css'
import 'xterm/css/xterm.css';
import "@fontsource-variable/jetbrains-mono";
import { files } from './files';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from 'xterm-addon-fit';
import { WebContainer, WebContainerProcess } from '@webcontainer/api';

let webcontainerInstance: WebContainer;
const appEl = document.querySelector<HTMLDivElement>('div#app')!;

// ### Main event listener
window.addEventListener('load', async () => {
  if (!termEl) {
    appEl.innerHTML = `
      <div>
        Failed to load terminal :'(<br />
        ${!termEl ? 'Terminal' : ''} not found
      </div>
    `;
    return;
  }

  // Terminal setup
  const fitAddon = new FitAddon();
  const term = new Terminal({
    convertEol: true,
  });
  term.loadAddon(fitAddon);
  term.open(termEl);
  fitAddon.fit();

  // Call only once
  webcontainerInstance = await WebContainer.boot();
  await webcontainerInstance.mount(files);

  // Wait for `server-ready` event
  // webcontainerInstance.on('server-ready', (port, url) => {
  //   iframeEl.src = url;
  // });

  const shellProcess = await startShell(term);
  window.addEventListener('resize', () => {
    fitAddon.fit();
    shellProcess.resize({
      cols: term.cols,
      rows: term.rows,
    });
  });
});

/**
 * Starts the main shell process
 *
 * @param terminal Terminal instance
 * @returns Shell process
 */
async function startShell(terminal: Terminal): Promise<WebContainerProcess> {
  const shellProcess = await webcontainerInstance.spawn('jsh', {
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
    })
  );


  const input = shellProcess.input.getWriter();

  terminal.onData((data) => {
    input.write(data);
  });

  return shellProcess;
};

// ### DOM Elements
const termEl = document.querySelector<HTMLDivElement>('div#terminal');
// const xtermViewportEl = document.querySelector<HTMLDivElement>('.xterm-viewport');

// xtermViewportEl!.style.backgroundColor = '';
