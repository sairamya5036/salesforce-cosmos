"""Stage a secret-free OAuth deployment outside the repository. Never retrieve secrets here."""
from pathlib import Path
import json
ROOT = Path(__file__).resolve().parents[2]
project = Path('/tmp/casepulse-oauth')
base = project/'force-app/main/default'
ns = 'http://soap.sforce.com/2006/04/metadata'
def write(folder,name,kind,body):
    p=base/folder/name; p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(f'<?xml version="1.0" encoding="UTF-8"?>\n<{kind} xmlns="{ns}">{body}</{kind}>\n')
write('externalClientApps','CasePulse.eca-meta.xml','ExternalClientApplication',
      '<contactEmail>sairamya945641@agentforce.com</contactEmail><description>Shared CasePulse MCP client registration.</description><distributionState>Local</distributionState><isProtected>false</isProtected><label>CasePulse AI</label>')
write('extlClntAppOauthSettings','CasePulse_OAuth.ecaOauth-meta.xml','ExtlClntAppOauthSettings',
      '<commaSeparatedOauthScopes>MCP,RefreshToken</commaSeparatedOauthScopes><externalClientApplication>CasePulse</externalClientApplication><label>CasePulse OAuth</label>')
write('extlClntAppGlobalOauthSets','CasePulse_Global.ecaGlblOauth-meta.xml','ExtlClntAppGlobalOauthSettings',
      '<callbackUrl>https://claude.ai/api/mcp/auth_callback\nhttps://oauth2.slack.com/external/auth/callback</callbackUrl><externalClientApplication>CasePulse</externalClientApplication><isConsumerSecretOptional>true</isConsumerSecretOptional><isNamedUserJwtEnabled>true</isNamedUserJwtEnabled><isPkceRequired>true</isPkceRequired><isSecretRequiredForRefreshToken>false</isSecretRequiredForRefreshToken><label>CasePulse Global OAuth</label><shouldRotateConsumerKey>false</shouldRotateConsumerKey><shouldRotateConsumerSecret>false</shouldRotateConsumerSecret>')
(project/'sfdx-project.json').write_text(json.dumps({'packageDirectories':[{'path':'force-app','default':True}],'sourceApiVersion':'68.0'}))
print('Staged /tmp/casepulse-oauth. No consumer keys or secrets are in this template.')
