# Record Presence: Real-Time Viewer Awareness for Salesforce Console
![Service Cloud Record Presence Info](assets/Service%20Cloud%20Record%20Presence%20Info.png)
![Sales Cloud Record Presence Info](assets/Sales%20Cloud%20Record%20Presence%20Info.png)


Record Presence is a reusable Salesforce Lightning Web Component that shows console users who else is viewing the same record in real time.

It helps service, sales, and operations teams avoid duplicate work, conflicting updates, and missed collaboration moments by giving users instant visibility into active teammates on the same record.

The component is designed as a configurable Lightning Console utility bar item, so admins can enable record awareness across multiple standard and custom objects without rebuilding presence logic for every business process.

## Why It Matters

In high-volume console environments, multiple users can open the same Case, Account, Opportunity, Work Order, or custom record at the same time.

Without visibility, teams risk:

- Duplicate investigation
- Conflicting customer conversations
- Accidental overwrite decisions
- Missed escalation opportunities
- Poor handoff between agents and teams

Record Presence gives users a lightweight collaboration signal before they edit, call, escalate, or close work.

## Key Capabilities

### Real-Time Record Awareness

When a user opens a supported record, Record Presence publishes a platform event and notifies other active users viewing that same record.

Users can immediately see who else is currently present on the record.

### Multi-User Presence Detection

The component supports multiple users viewing the same record at once.

When a new user joins a record:

- Existing viewers are notified.
- The new user receives presence responses from current viewers.
- The viewer list updates automatically.

### Configurable Across Objects

Admins can configure which objects participate in presence tracking.

Examples:

```text
Case
Case,Account,Contact
Case,Account,Opportunity,Custom_Object__c
```

This allows one utility component to support service, sales, operations, fulfillment, and custom business processes.

### Configurable Display Fields

Admins can choose which fields appear in the utility panel for each object.

Example:

```text
Case=CaseNumber,Subject,Status;
Account=Name,Industry;
Opportunity=Name,StageName,Amount
```

This gives users meaningful context without hardcoding object-specific UI logic.

### Automatic Leave Detection

When a user changes records, closes the utility, leaves the page, or the component disconnects, Record Presence publishes a `Left` event so other viewers can remove that user from the active viewer list.

### Built for Lightning Console

Record Presence uses:

- Lightning Utility Bar
- Salesforce Workspace API
- Lightning EMP API
- Platform Events
- Apex event publishing
- UI Record API

It is built for Salesforce Console apps where agents and reps work across tabs, subtabs, and high-volume records.

## Architecture Overview

1. The utility detects the focused console record.
2. If the object is allowed, the component publishes a `Viewing` event.
3. Other users on the same record receive the event through EMP API.
4. Existing viewers respond with a `Present` event.
5. The component updates the viewer list in real time.
6. When a user leaves the record, a `Left` event removes them from other users' panels.

## Included Metadata

This project includes:

- `recordPresence` Lightning Web Component
- `RecordPresenceController` Apex controller
- `RecordPresenceEvent__e` platform event
- `Record_Presence_User` permission set
- Apex test coverage for event publishing

## Best Use Cases

Record Presence is ideal for:

- Service Console case handling
- Sales Console account collaboration
- Escalation management
- Fulfillment and operations consoles
- Custom record review workflows
- High-volume support teams
- Any process where multiple users may touch the same record

## Key Highlights

This is not just a UI component. It demonstrates a reusable Salesforce architecture pattern for real-time collaboration using platform-native capabilities.

It highlights:

- Event-driven architecture
- Reusable LWC design
- Admin-first configuration
- Console app awareness
- Multi-object scalability
- Practical business value
- Clean separation between UI, Apex, and platform events

Record Presence is a lightweight, extensible foundation for building more collaborative Salesforce Console experiences.

## Installation

### 1. Authenticate to Your Salesforce Org

```bash
sf org login web --alias record-presence-org
```

Replace `record-presence-org` with your preferred org alias.

### 2. Deploy the Source

```bash
sf project deploy start --source-dir force-app --target-org record-presence-org
```

### 3. Assign the Permission Set

Assign the included permission set to users who should use Record Presence:

```bash
sf org assign permset --name Record_Presence_User --target-org record-presence-org
```

This grants access to the Apex controller and create/read access to the `RecordPresenceEvent__e` platform event.

To assign it to a specific user:

```bash
sf org assign permset --name Record_Presence_User --target-org record-presence-org --on-behalf-of user@example.com
```

### 4. Validate the Deployment

```bash
sf apex run test --class-names RecordPresenceControllerTest --target-org record-presence-org --result-format human
```

## Add Record Presence to a Lightning Console App

1. In Salesforce Setup, go to **App Manager**.
2. Find the Lightning Console app where you want presence tracking.
3. Open the row action menu and select **Edit**.
4. Go to **Utility Items**.
5. Click **Add Utility Item**.
6. Search for and select **Record Presence**.
7. Set the utility properties:
   - **Label**: `Record Presence`
   - **Icon**: Choose an icon that fits your app.
   - **Panel Width** and **Panel Height**: Size the utility for your team.
   - **Start Automatically**: Recommended so presence is active in the background as soon as users open the console app.
8. Configure the component properties described below.
9. Save the app.

## Component Configuration

Record Presence is designed to be configured by admins from the Lightning App Builder utility item settings.

### Allowed Object API Names

Comma-separated object API names that should publish and receive presence.

Default:

```text
Case
```

Examples:

```text
Case,Account
Case,Account,Contact,Opportunity
Case,Custom_Object__c
```

Only records whose object API name appears in this list will be tracked.

### Display Field Configuration

Semicolon-separated object-to-fields configuration. Each object entry uses this format:

```text
ObjectApiName=Field1,Field2,Field3
```

Default:

```text
Case=CaseNumber,Subject,Status
```

Multi-object example:

```text
Case=CaseNumber,Subject,Status;Account=Name,Industry;Opportunity=Name,StageName,Amount
```

Custom object example:

```text
Custom_Object__c=Name,Status__c,Priority__c
```

Use fields that assigned users can read. If a configured field is unavailable or blank, the component does not display that field.

### Utility Title

The heading shown inside the utility panel.

Recommended:

```text
Active Record Viewers
```

Other examples:

```text
Record Presence
Active Viewers
Team Presence
```

## Recommended Configurations

### Service Console

```text
Allowed Object API Names:
Case,Account,Contact

Display Field Configuration:
Case=CaseNumber,Subject,Status;Account=Name,Industry;Contact=Name,Email

Utility Title:
Active Record Viewers
```

### Sales Console

```text
Allowed Object API Names:
Account,Opportunity,Contact

Display Field Configuration:
Account=Name,Industry;Opportunity=Name,StageName,Amount;Contact=Name,Title,Email

Utility Title:
Active Record Viewers
```

### Operations Console

```text
Allowed Object API Names:
Work_Order__c,Shipment__c,Escalation__c

Display Field Configuration:
Work_Order__c=Name,Status__c,Priority__c;Shipment__c=Name,Tracking_Number__c,Status__c;Escalation__c=Name,Severity__c,OwnerId

Utility Title:
Team Presence
```

## Admin Notes

- Add the component to Lightning Console apps through the utility bar.
- Enable **Start Automatically** for the best background notification experience.
- Assign `Record_Presence_User` to every user who should participate in presence tracking.
- Include every object you want to track in **Allowed Object API Names**.
- Include readable fields in **Display Field Configuration** for useful record context.
- For custom objects and custom fields, use full API names such as `Project__c` and `Status__c`.
