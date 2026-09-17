"""Independent SPDX 2.3 semantic validation; required, not an optional gate."""
import importlib.metadata
import sys

from spdx_tools.spdx.parser.parse_anything import parse_file
from spdx_tools.spdx.validation.document_validator import validate_full_spdx_document

if importlib.metadata.version("spdx-tools") != "0.8.5":
    sys.exit("Install the pinned tests/requirements-artifacts.txt validator")
messages = validate_full_spdx_document(parse_file(sys.argv[1]))
for message in messages:
    print(message, file=sys.stderr)
sys.exit(bool(messages))
