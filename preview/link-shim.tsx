"use client";

import { navigate } from "./next-shim";

/** `next/link` stand-in for the single-file preview build. */
export default function Link({
  href,
  children,
  ...rest
}: {
  href: string;
  children: React.ReactNode;
} & React.AnchorHTMLAttributes<HTMLAnchorElement>) {
  return (
    <a
      href={`#${href}`}
      onClick={(e) => {
        e.preventDefault();
        navigate(href);
      }}
      {...rest}
    >
      {children}
    </a>
  );
}
