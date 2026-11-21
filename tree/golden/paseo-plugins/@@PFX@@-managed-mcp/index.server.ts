import type { PluginServerContext } from "@getpaseo/plugin/server";

export default function contribute(server: PluginServerContext) {
  server.before("agent.create", ({ request }) => {
    if (request.config.provider !== "antigravity") {
      return request;
    }

    if (request.config.mcpServers?.["korean-law"]) {
      return request;
    }

    return {
      ...request,
      config: {
        ...request.config,
        mcpServers: {
          ...request.config.mcpServers,
          "korean-law": {
            type: "http",
            url: "http://korean-law-gateway:3000/mcp",
          },
        },
      },
    };
  });

  return () => {};
}
