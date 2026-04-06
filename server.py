"""
Wrapper script to run the Fabric RTI MCP server from the root directory.

This provides a convenient entry point for local development and testing,
and serves as the entry point for Azure Functions custom handler deployment.
"""

import os
import sys

# Add the current directory to the Python path so fabric_rti_mcp can be imported
# This is necessary for Azure Functions deployment where the package isn't installed
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

from fabric_rti_mcp.server import main

if __name__ == "__main__":
    main()
