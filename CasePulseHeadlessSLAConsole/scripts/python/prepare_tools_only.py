"""Stage the same MCP server without its HXL resource while HXL beta is disabled."""
from pathlib import Path
import json
import xml.etree.ElementTree as ET
ROOT = Path(__file__).resolve().parents[2]
ns = 'http://soap.sforce.com/2006/04/metadata'
ET.register_namespace('', ns)
server = ET.parse(ROOT/'force-app/main/default/mcpServerDefinitions/CasePulse.mcpServerDefinition-meta.xml')
for resource in server.getroot().findall('{%s}resources' % ns):
    server.getroot().remove(resource)
for tool in server.getroot().findall('{%s}tools' % ns):
    for resource in tool.findall('{%s}uiResource' % ns):
        tool.remove(resource)
project = Path('/tmp/casepulse-tools')
target = project/'force-app/main/default/mcpServerDefinitions/CasePulse.mcpServerDefinition-meta.xml'
target.parent.mkdir(parents=True, exist_ok=True)
server.write(target, encoding='UTF-8', xml_declaration=True)
(project/'sfdx-project.json').write_text(json.dumps({'packageDirectories':[{'path':'force-app','default':True}],'sourceApiVersion':'68.0'}))
print('Staged /tmp/casepulse-tools. Deploy CasePulse from that project; HXL remains in the main source.')
