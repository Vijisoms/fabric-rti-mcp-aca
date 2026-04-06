#!/usr/bin/env python3
"""Setup script for creating the Fabricrti-agent in Azure AI Foundry with MCP tools."""

import argparse
import json
import os
import sys

try:
    from azure.identity import DefaultAzureCredential
    from azure.ai.projects import AIProjectClient
except ImportError:
    print("Required packages not installed. Run:")
    print("  pip install azure-identity azure-ai-projects")
    sys.exit(1)

AGENT_DEFINITION_PATH = os.path.join(os.path.dirname(__file__), ".foundry", "agent-definition.json")


def load_agent_definition(path: str) -> dict:
    with open(path) as f:
        return json.load(f)


def create_agent(project_endpoint: str, definition: dict) -> None:
    credential = DefaultAzureCredential()
    client = AIProjectClient(endpoint=project_endpoint, credential=credential)

    mcp_tools = []
    for tool in definition["tools"]:
        mcp_tools.append(
            {
                "type": "mcp",
                "mcp": {
                    "server_label": tool["name"],
                    "server_url": tool["server_url"],
                },
            }
        )

    agent = client.agents.create_agent(
        model="gpt-4o",
        name=definition["name"],
        instructions=definition["instructions"],
        description=definition["description"],
        tools=mcp_tools,
    )

    print(f"Agent created successfully!")
    print(f"  Name: {agent.name}")
    print(f"  ID:   {agent.id}")
    print(f"  Tools: {[t['name'] for t in definition['tools']]}")
    return agent


def main() -> None:
    parser = argparse.ArgumentParser(description="Create Fabricrti-agent in Azure AI Foundry")
    parser.add_argument(
        "--project-endpoint",
        default="https://aifoundryhub9616386474.services.ai.azure.com/api/projects/aifoundryhub9616386474-project",
        help="Azure AI Foundry project endpoint URL",
    )
    parser.add_argument(
        "--definition",
        default=AGENT_DEFINITION_PATH,
        help="Path to agent-definition.json",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the agent configuration without creating it",
    )
    args = parser.parse_args()

    definition = load_agent_definition(args.definition)

    if args.dry_run:
        print("Agent configuration (dry run):")
        print(json.dumps(definition, indent=2))
        return

    create_agent(args.project_endpoint, definition)


if __name__ == "__main__":
    main()
