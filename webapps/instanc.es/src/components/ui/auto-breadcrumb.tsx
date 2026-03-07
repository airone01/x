import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
  BreadcrumbEllipsis,
} from "@/components/ui/breadcrumb"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { headers } from 'next/headers'

const MAX_VISIBLE_SEGMENTS = 3

export async function AutoBreadcrumb() {
  const headersList = await headers()
  const pathname = headersList.get("x-pathname") ?? "/"
  const segments = pathname.split('/').filter(Boolean)

  const capitalizeAndClean = (text: string) => {
    return text
      .split('-')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ')
  }

  const renderSegments = () => {
    if (segments.length <= MAX_VISIBLE_SEGMENTS) {
      return segments.map((segment, index) => {
        const path = `/${segments.slice(0, index + 1).join('/')}`
        const isLast = index === segments.length - 1

        return (
          <>
            <BreadcrumbSeparator key={`sep-${index}`} />
            <BreadcrumbItem key={segment}>
              {isLast ? (
                <BreadcrumbPage>{capitalizeAndClean(segment)}</BreadcrumbPage>
              ) : (
                <BreadcrumbLink href={path}>
                  {capitalizeAndClean(segment)}
                </BreadcrumbLink>
              )}
            </BreadcrumbItem>
          </>
        )
      })
    }

    const hiddenSegments = segments.slice(1, -2)
    const lastSegments = segments.slice(-2)

    return (
      <>
        <BreadcrumbSeparator />
        <BreadcrumbItem>
          <DropdownMenu>
            <DropdownMenuTrigger className="flex items-center gap-1">
              <BreadcrumbEllipsis className="h-4 w-4" />
              <span className="sr-only">Toggle menu</span>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="start">
              {hiddenSegments.map((segment, index) => {
                const path = `/${segments.slice(0, index + 2).join('/')}`
                return (
                  <DropdownMenuItem key={segment} asChild>
                    <BreadcrumbLink href={path}>
                      {capitalizeAndClean(segment)}
                    </BreadcrumbLink>
                  </DropdownMenuItem>
                )
              })}
            </DropdownMenuContent>
          </DropdownMenu>
        </BreadcrumbItem>
        {lastSegments.map((segment, index) => {
          const path = `/${segments.slice(0, segments.length - 2 + index + 1).join('/')}`
          const isLast = index === lastSegments.length - 1

          return (
            <>
              <BreadcrumbSeparator key={`sep-${index}`} />
              <BreadcrumbItem key={segment}>
                {isLast ? (
                  <BreadcrumbPage>{capitalizeAndClean(segment)}</BreadcrumbPage>
                ) : (
                  <BreadcrumbLink href={path}>
                    {capitalizeAndClean(segment)}
                  </BreadcrumbLink>
                )}
              </BreadcrumbItem>
            </>
          )
        })}
      </>
    )
  }

  return (
    <Breadcrumb>
      <BreadcrumbList>
        <BreadcrumbItem>
          <BreadcrumbLink href="/">Home</BreadcrumbLink>
        </BreadcrumbItem>
        {renderSegments()}
      </BreadcrumbList>
    </Breadcrumb>
  )
}
