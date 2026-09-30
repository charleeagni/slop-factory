import Foundation

/// Runs only after a durable sharing choice. It reads X's own account anchor.
public enum XAccountObservationScript {
    public static let messageName = "slopXAccount"
    public static let source = #"""
    (() => {
      const context = window.__slopXAccountContext;
      if (!context) return;
      window.__slopXAccountObserver?.stop();
      if (window !== window.top || location.protocol !== 'https:' ||
          !['x.com', 'www.x.com'].includes(location.hostname) || location.port) return;
      const reserved = new Set('about account accounts compose download explore hashtag home i intent login logout messages notifications privacy search settings share signup tos help jobs oauth premium communities connect_people who_to_follow welcome'.split(' '));
      let last;
      let stopped = false;
      const observe = () => {
        if (stopped) return;
        const signedOut = /^\/(?:login|logout|signup|i\/flow)(?:\/|$)/i.test(location.pathname);
        const anchor = signedOut ? null : document.querySelector('a[data-testid="AppTabBar_Profile_Link"]');
        let href = null;
        let handle = null;
        try {
          const raw = anchor?.getAttribute('href');
          const candidate = raw ? new URL(raw, location.href) : null;
          const match = candidate?.pathname.match(/^\/([A-Za-z0-9_]{1,15})\/?$/);
          if (candidate?.origin === location.origin && !candidate.username && !candidate.password &&
              match && !reserved.has(match[1].toLowerCase())) {
            href = candidate;
            handle = match[1].toLowerCase();
          }
        } catch (_) { /* A malformed or absent anchor clears the current observation. */ }
        if (handle === last) return;
        last = handle;
        window.webkit.messageHandlers.slopXAccount.postMessage({ generation: context.generation, session: context.session, handle, href: href?.href ?? null });
      };
      observe();
      let debounce;
      const observer = new MutationObserver(() => {
        if (stopped) return;
        clearTimeout(debounce);
        debounce = setTimeout(observe, 400);
      });
      observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['href', 'data-testid'] });
      const interval = setInterval(observe, 2000);
      window.__slopXAccountObserver = { stop() {
        stopped = true;
        observer.disconnect();
        clearInterval(interval);
        clearTimeout(debounce);
        last = undefined;
      } };
    })();
    """#
    public static let stop = "window.__slopXAccountObserver?.stop(); delete window.__slopXAccountObserver; delete window.__slopXAccountContext;"

    public static func start(generation: UUID, session: UUID) -> String {
        "window.__slopXAccountContext = { generation: '\(generation.uuidString)', session: '\(session.uuidString)' };\n" + source
    }
}
