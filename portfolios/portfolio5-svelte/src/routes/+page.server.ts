export function load({ setHeaders }: { setHeaders: (headers: Record<string, string>) => void }) {
    setHeaders({
        'Cross-Origin-Embedder-Policy': 'require-corp',
        'Cross-Origin-Opener-Policy': 'same-origin',
    });
}
