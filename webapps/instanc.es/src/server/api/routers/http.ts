import { z } from "zod";

import {
  createTRPCRouter,
  publicProcedure,
} from "@/server/api/trpc";

export const postRouter = createTRPCRouter({
  getHttpNormalResponse: publicProcedure
    .input(z.object({ url: z.string().url() }))
    .query(async ({ input }) => {
      try {
        const response = await fetch(input.url);
        const body = await response.text();
        return {
          status: response.status,
          body,
        };
      } catch (error) {
        return {
          status: 500,
          body: error instanceof Error ? error.message : "Unknown error",
        };
      }
    }),
});
