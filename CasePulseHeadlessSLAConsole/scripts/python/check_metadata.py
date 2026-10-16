"""Check metadata integrity and safety contracts without a Salesforce connection."""
from pathlib import Path
import json
import re
import xml.etree.ElementTree as ET
ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT/'force-app/main/default'
NS = {'m':'http://soap.sforce.com/2006/04/metadata'}
for path in BASE.rglob('*.xml'):
    ET.parse(path)
for path in BASE.rglob('*.json'):
    json.loads(path.read_text())
widget = BASE/'uiWidgets/casePulseConsole'
composition=json.loads((widget/'casePulseConsole.json').read_text())
props=json.loads((widget/'schema.json').read_text())['properties']['attributes']['properties']
assert composition['contentBody']['widgetBody']['definition']=='tile/widget'
renderer=json.loads((BASE/'lightningTypes/analyzeCaseRisk/renderer.json').read_text())['renderer']['componentOverrides']['$']
assert renderer['definition']=='@widget/c/casePulseConsole'
assert set(renderer['attributes'])==set(props)
for key,binding in renderer['attributes'].items():
    assert binding=='{!$attrs.outputValues.console.'+key+'}'
refs=set(re.findall(r'\$attrs\.(\w+)',json.dumps(composition)))
assert refs <= set(props), refs-set(props)
case_src=(BASE/'classes/CaseRiskAnalyzer.cls').read_text().split('global class RiskCase')[1].split('@InvocableMethod')[0]
case_fields=set(re.findall(r'global\s+\w+\s+(\w+)\s*(?:[;=])',case_src))
case_refs=set(re.findall(r'\$case\.(\w+)',json.dumps(composition)))
assert case_refs <= case_fields, case_refs-case_fields
for binding in renderer['attributes'].values():
    field=re.search(r'console\.(\w+)',binding)[1]
    assert re.search(r'global\s+[\w<>]+\s+'+field+r'\b', (BASE/'classes/CaseRiskAnalyzer.cls').read_text())
server=ET.parse(BASE/'mcpServerDefinitions/CasePulse.mcpServerDefinition-meta.xml')
tools=server.findall('m:tools',NS)
assert {t.findtext('m:toolName',namespaces=NS) for t in tools}=={'analyzeCaseRisk','prepareCaseRescue'}
assert 'CaseRescueApply' not in ''.join(t.findtext('m:apiDefinition/m:operation',namespaces=NS) for t in tools)
for t in tools:
    assert t.findtext('m:readOnly',namespaces=NS)=='true'
resource=server.find('m:resources',NS)
assert resource.findtext('m:resourceUri',namespaces=NS)=='ui://widget/lightningType/c__analyzeCaseRisk'
assert tools[0].findtext('m:uiResource',namespaces=NS)==resource.findtext('m:resourceName',namespaces=NS)
assert not (BASE/'lightningTypes/analyzeCaseRiskResponse/renderer.json').exists()
flow=ET.parse(BASE/'flows/CasePulse_Confirm_Rescue.flow-meta.xml')
for screen in flow.findall('m:screens',NS):
    for field in screen.findall('m:fields',NS):
        if field.findtext('m:fieldType',namespaces=NS)=='DisplayText':
            text=field.findtext('m:fieldText',namespaces=NS)
            assert '<h2>' in text and '</h2>' in text, 'Missing valid rich-text heading'
            assert not re.search(r'<\s+/?\w|</\s+\w',text), 'Formatter corrupted rich-text tags'
approval=flow.find("m:screens[m:name='Confirm']/m:fields[m:name='approval']",NS)
assert approval.findtext('m:defaultValue/m:booleanValue',namespaces=NS)=='false'
assert flow.findtext("m:screens[m:name='Confirm']/m:allowFinish",namespaces=NS)=='true'
apply=flow.find("m:actionCalls[m:name='Apply']",NS)
assert apply.findtext("m:inputParameters[m:name='approved']/m:value/m:elementReference",namespaces=NS)=='approval'
permissions=ET.parse(BASE/'permissionsets/CasePulse_User.permissionset-meta.xml')
for access in permissions.findall('m:flowAccesses',NS):
    name=access.findtext('m:flow',namespaces=NS)
    assert (BASE/'flows'/(name+'.flow-meta.xml')).is_file(), f'Invalid Flow reference: {name!r}'
marker=permissions.find("m:fieldPermissions[m:field='Case.CasePulse_Rescue_Task__c']",NS)
assert marker.findtext('m:editable',namespaces=NS)=='false'
for path in BASE.rglob('*'):
    if path.is_file():
        assert not re.search(r'<consumer(?:Key|Secret)>',path.read_text()), f'Credential in {path}'
print('PASS: XML/JSON parse, HXL bindings and Apex field trace, nested renderer, two read-only MCP tools, approval wiring, private marker, and credential exclusion.')
