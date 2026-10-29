// Line icons drawn in currentColor, and the Obsidian logo.
import type { ReactNode, SVGProps } from "react";

const Icon = ({ children, ...p }: SVGProps<SVGSVGElement> & { children: ReactNode }) => (
  <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" {...p}>
    {children}
  </svg>
);

export const Logo = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 1080 1050" aria-hidden="true" {...p}>
    <path fillRule="evenodd" fill="currentColor" d="M435 0H645L962 196V632L1072 772L791 981L745 952L681 1050H398L295 952L260 981L7 772L117 632V196ZM539 108L618 268L778 348L618 427L539 587L460 427L300 348L460 268ZM216 713a95 95 0 1 0 190 0a95 95 0 1 0 -190 0ZM673 713a95 95 0 1 0 190 0a95 95 0 1 0 -190 0ZM473 925L537 825L601 925L574 944L537 910L500 944Z" />
  </svg>
);

export const ModsIcon = () => <Icon><path d="M4 6h16M4 12h16M4 18h16" /></Icon>;
export const ProfilesIcon = () => <Icon><circle cx="12" cy="8" r="4" /><path d="M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6" /></Icon>;
export const CogIcon = () => (
  <Icon>
    <circle cx="12" cy="12" r="3" />
    <path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" />
  </Icon>
);
export const PurgeIcon = () => <Icon><path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6" /></Icon>;
export const DeployIcon = () => <Icon><path d="M12 3v12M7 10l5 5 5-5M4 19h16" /></Icon>;
export const PlayIcon = () => <Icon fill="currentColor" stroke="none"><path d="M7 4.5v15l13-7.5z" /></Icon>;
export const WarnIcon = () => <Icon><path d="M12 3l10 18H2zM12 10v5M12 17.5v.5" /></Icon>;
export const SearchIcon = () => <Icon><circle cx="11" cy="11" r="7" /><path d="M20 20l-4-4" /></Icon>;
export const ChevronIcon = () => <Icon><path d="M6 9l6 6 6-6" /></Icon>;
export const GripIcon = () => <Icon><path d="M5 8h14M5 12h14M5 16h14" /></Icon>;
export const CloseIcon = () => <Icon><path d="M6 6l12 12M18 6L6 18" /></Icon>;
export const ResetIcon = () => <Icon><path d="M4 4v6h6M4.5 15a8 8 0 1 0 1.5-8.5L4 10" /></Icon>;
