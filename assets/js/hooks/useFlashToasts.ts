import * as React from "react";
import { usePage } from "@inertiajs/react";
import { toast } from "@/components/ui/sonner";
import type { SharedProps } from "@/types";

/**
 * Transforma as flash messages do Phoenix em toasts.
 *
 * O Inertia reenvia os mesmos props em reloads parciais, então guardamos a
 * assinatura da última flash exibida — sem isso, o mesmo aviso reapareceria a
 * cada re-render.
 */
export function useFlashToasts() {
  const { flash } = usePage<SharedProps>().props;
  const lastShown = React.useRef<string | null>(null);

  React.useEffect(() => {
    if (!flash) return;

    const signature = JSON.stringify(flash);
    if (signature === lastShown.current) return;
    lastShown.current = signature;

    Object.entries(flash).forEach(([kind, message]) => {
      if (kind === "error") {
        toast.error(message);
      } else {
        toast.success(message);
      }
    });
  }, [flash]);
}
