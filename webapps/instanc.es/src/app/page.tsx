import type { Metadata } from 'next'
import { Icon } from '@iconify/react';
import { Button } from '@/components/ui/button'
import { ExternalLinkIcon } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { SvgGridDeco } from '@/components/svg-grid-deco'
import Link from 'next/link';

export const metadata: Metadata = {
  title: 'instanc.es',
  applicationName: 'instanc.es',
  openGraph: { title: 'instanc.es' },
  appLinks: { web: { url: 'https://instanc.es' } },
}

export default function Page() {
  return (
    <>
      <section className="relative overflow-hidden py-32">
        <div className="container">
          <div className="absolute inset-x-0 top-0 z-10 flex size-full items-center justify-center opacity-100">
            <SvgGridDeco />
          </div>
          <div className="mx-auto flex max-w-5xl flex-col items-center">
            <div className="z-10 flex flex-col items-center gap-6 text-center">
              <Badge variant="outline" className='bg-background'><div className='bg-green-400 w-3 h-3 rounded-full mr-1' /> Online</Badge>
              <div>
                <h1 className="mb-6 text-pretty text-2xl font-bold lg:text-5xl">
                  Welcome to <code className='relative rounded-lg border bg-muted px-[0.3rem] py-[0.2rem] font-mono font-semibold'>instanc.es</code>
                </h1>
                <p className="text-muted-foreground lg:text-xl">
                  Here you can find instances and mirrors of your favorite Linux Distros, programs, and more! Hit {" "}
                  <kbd className="pointer-events-none inline-flex h-5 select-none items-center gap-1 text-sm rounded border bg-muted px-1.5 font-mono font-medium text-muted-foreground opacity-100">
                    <span className="text-base lg:text-lg">⌘</span>K
                  </kbd> {" "}
                  to search for an instance.
                </p>
              </div>
              <div className="mt-4 flex justify-center gap-2">
                <Button>Get Started</Button>
                <Button variant="outline">
                  Learn more <ExternalLinkIcon className="ml-2 h-4" />
                </Button>
              </div>
              <div className="mt-20 flex flex-col items-center gap-4">
                <p className="text-center: text-muted-foreground lg:text-left">
                  Built with open-source technologies
                </p>
                <div className="flex flex-wrap items-center justify-center gap-4">
                  <Link href="https://nextjs.org/">
                    <Button variant='outline' className='w-9 h-9'>
                      <Icon icon="simple-icons:nextdotjs" />
                    </Button>
                  </Link>
                  <Link href="https://ui.shadcn.com/">
                    <Button variant='outline' className='w-9 h-9'>
                      <Icon icon="simple-icons:shadcnui" />
                    </Button>
                  </Link>
                  <Link href="https://www.typescriptlang.org/">
                    <Button variant='outline' className='w-9 h-9'>
                      <Icon icon="simple-icons:typescript" />
                    </Button>
                  </Link>
                  <Link href="https://react.dev/">
                    <Button variant='outline' className='w-9 h-9'>
                      <Icon icon="simple-icons:react" />
                    </Button>
                  </Link>
                  <Link href="https://tailwindcss.com/">
                    <Button variant='outline' className='w-9 h-9'>
                      <Icon icon="simple-icons:tailwindcss" />
                    </Button>
                  </Link>
                  <Link href="https://trpc.io/">
                    <Button variant='outline' className='w-9 h-9'>
                      <Icon icon="simple-icons:trpc" />
                    </Button>
                  </Link>
                  <Link href="https://supabase.com/database">
                    <Button variant='outline' className='w-9 h-9'>
                      <Icon icon="simple-icons:postgresql" />
                    </Button>
                  </Link>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>
    </>
  )
}
