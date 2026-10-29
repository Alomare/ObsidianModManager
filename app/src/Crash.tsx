// If the page fails to render, this shows what went wrong instead of an empty window.
import { Component, type ReactNode } from "react";

export class Crash extends Component<{ children: ReactNode }, { error: Error | null }> {
  state = { error: null as Error | null };
  static getDerivedStateFromError(error: Error) {
    return { error };
  }
  render() {
    const e = this.state.error;
    if (!e) return this.props.children;
    return (
      <div className="crash">
        <h1 className="cap">Obsidian</h1>
        <p>The window stopped working. Restart Obsidian; if this happens again, please report the text below.</p>
        <pre>{`${e.message}\n\n${e.stack ?? ""}`}</pre>
      </div>
    );
  }
}
