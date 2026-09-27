import * as Sentry from "@sentry/nextjs";
import { opcoesSentry } from "@/lib/sentry/opcoes";

Sentry.init(opcoesSentry);
