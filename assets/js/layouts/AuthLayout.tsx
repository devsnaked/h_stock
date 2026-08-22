import * as React from "react";
import { Head } from "@inertiajs/react";
import { Scale } from "lucide-react";
import { Toaster } from "@/components/ui/sonner";
import { useFlashToasts } from "@/hooks/useFlashToasts";

/** Telas públicas de autenticação. Card único, centralizado, sem navegação. */
export const AuthLayout: React.FC<{
  title: string;
  subtitle?: string;
  children: React.ReactNode;
  footer?: React.ReactNode;
}> = ({ title, subtitle, children, footer }) => {
  useFlashToasts();

  return (
    <div className="flex min-h-dvh flex-col justify-center bg-background px-4 py-10 text-foreground">
      <Head title={title} />
      <Toaster />

      <div className="mx-auto w-full max-w-sm space-y-6">
        <div className="flex flex-col items-center text-center">
          <div className="flex size-14 items-center justify-center rounded-2xl bg-primary text-primary-foreground">
            <Scale className="size-7" />
          </div>
          <h1 className="mt-4 text-xl font-semibold tracking-tight">{title}</h1>
          {subtitle && <p className="mt-1 text-sm text-muted-foreground">{subtitle}</p>}
        </div>

        <div className="rounded-xl border border-border bg-card p-5 shadow-sm">
          {children}
        </div>

        {footer && (
          <div className="text-center text-sm text-muted-foreground">{footer}</div>
        )}
      </div>
    </div>
  );
};
