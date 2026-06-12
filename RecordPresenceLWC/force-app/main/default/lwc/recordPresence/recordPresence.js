import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { subscribe, unsubscribe, onError } from "lightning/empApi";
import { CurrentPageReference } from "lightning/navigation";
import {
  getAllTabInfo,
  getFocusedTabInfo,
  IsConsoleNavigation
} from "lightning/platformWorkspaceApi";
import USER_ID from "@salesforce/user/Id";
import publishEvent from "@salesforce/apex/RecordPresenceController.publishEvent";
import { getRecord } from "lightning/uiRecordApi";

const CHANNEL_NAME = "/event/RecordPresenceEvent__e";
const DEFAULT_ALLOWED_OBJECTS = "Case";
const DEFAULT_FIELD_CONFIG = "Case=CaseNumber,Subject,Status";

export default class RecordPresence extends LightningElement {
  @api recordId;
  @api objectApiName;
  @api allowedObjectApiNames = DEFAULT_ALLOWED_OBJECTS;
  @api fieldConfig = DEFAULT_FIELD_CONFIG;
  @api utilityTitle = "Who Else Is Watching";

  viewers = [];
  displayFields = [];
  subscription;
  activeRecordId;
  activeObjectApiName;
  currentPageReference;
  hasAnnouncedPresence = false;
  isSubscribed = false;
  isResolvingRecord = false;
  recordContextInterval;
  lastEventSummary = "Waiting for platform event subscription.";

  @wire(IsConsoleNavigation)
  wiredIsConsoleNavigation(value) {
    this.isConsoleNavigation = value;
    this.resolveActiveRecord();
  }

  @wire(CurrentPageReference)
  wiredCurrentPageReference(pageReference) {
    this.currentPageReference = pageReference;
    this.resolveActiveRecord();
  }

  @wire(getRecord, {
    recordId: "$activeRecordId",
    fields: "$recordFieldApiNames"
  })
  wiredRecord({ data, error }) {
    if (data) {
      this.displayFields = this.configuredFieldNames
        .map((fieldName) => {
          const field = data.fields?.[this.getFieldKey(fieldName)];
          const value = field?.displayValue ?? field?.value;

          return {
            name: fieldName,
            label: this.getFieldLabel(fieldName),
            value:
              value === undefined || value === null || value === ""
                ? "Unavailable"
                : value
          };
        })
        .filter((field) => field.value !== "Unavailable");
    } else if (error) {
      this.displayFields = [];
      console.error("Error loading configured record fields", error);
    } else {
      this.displayFields = [];
    }
  }

  connectedCallback() {
    this.handleSubscribe();
    this.registerErrorListener();
    this.resolveActiveRecord();
    this.recordContextInterval = window.setInterval(
      this.resolveActiveRecord,
      3000
    );
    window.addEventListener("focus", this.resolveActiveRecord);
    window.addEventListener("beforeunload", this.handleUnload);
    document.addEventListener("visibilitychange", this.handleVisibilityChange);
  }

  disconnectedCallback() {
    window.clearInterval(this.recordContextInterval);
    window.removeEventListener("focus", this.resolveActiveRecord);
    window.removeEventListener("beforeunload", this.handleUnload);
    document.removeEventListener(
      "visibilitychange",
      this.handleVisibilityChange
    );
    this.leaveActiveRecord();
    this.handleUnsubscribe();
  }

  get isConsole() {
    return (
      this.isConsoleNavigation === true ||
      this.isConsoleNavigation?.data === true
    );
  }

  get allowedObjects() {
    return this.parseCommaList(
      this.allowedObjectApiNames || DEFAULT_ALLOWED_OBJECTS
    );
  }

  get fieldConfigByObject() {
    return this.parseFieldConfig(this.fieldConfig || DEFAULT_FIELD_CONFIG);
  }

  get configuredFieldNames() {
    if (!this.activeObjectApiName) {
      return [];
    }

    return this.fieldConfigByObject.get(this.activeObjectApiName) || [];
  }

  get recordFieldApiNames() {
    if (
      !this.activeRecordId ||
      !this.activeObjectApiName ||
      !this.configuredFieldNames.length
    ) {
      return undefined;
    }

    return this.configuredFieldNames.map(
      (fieldName) => `${this.activeObjectApiName}.${fieldName}`
    );
  }

  get currentRecordLabel() {
    return this.displayFields[0]?.value || this.activeRecordId;
  }

  get statusMessage() {
    if (!this.isSubscribed) {
      return "Presence is starting. Open this utility item or enable Start Automatically for background alerts.";
    }

    if (!this.activeRecordId) {
      return "Presence is listening, but no configured focused record has been detected yet.";
    }

    return `${this.lastEventSummary} ${this.activeObjectApiName}: ${this.currentRecordLabel}`;
  }

  get emptyViewerMessage() {
    return "You are the only one viewing this record.";
  }

  handleUnload = () => {
    this.leaveActiveRecord();
  };

  handleVisibilityChange = () => {
    if (!document.hidden) {
      this.resolveActiveRecord();
    }
  };

  resolveActiveRecord = async () => {
    if (this.isResolvingRecord) {
      return;
    }

    this.isResolvingRecord = true;

    try {
      const nextRecord = await this.getActiveRecord();
      this.setActiveRecord(nextRecord);
    } catch (error) {
      console.error("Error resolving focused record", error);
    } finally {
      this.isResolvingRecord = false;
    }
  };

  async getActiveRecord() {
    if (this.isConsole) {
      try {
        const tabInfo = await getFocusedTabInfo();
        const focusedRecord = this.extractAllowedRecord(tabInfo);

        if (focusedRecord) {
          return focusedRecord;
        }
      } catch (error) {
        console.error("Error reading focused console tab", error);
      }

      try {
        const allTabInfo = await getAllTabInfo();
        const selectedRecord = this.extractAllowedRecordFromTabs(allTabInfo);

        if (selectedRecord) {
          return selectedRecord;
        }
      } catch (error) {
        console.error("Error reading console tab list", error);
      }
    }

    return (
      this.extractAllowedRecord(this.currentPageReference) ||
      this.extractAllowedRecord({
        recordId: this.recordId,
        objectApiName: this.objectApiName
      })
    );
  }

  extractAllowedRecordFromTabs(tabs = []) {
    const selectedTabs = tabs.filter(
      (tab) => tab.highlighted || tab.focused || tab.active
    );
    const candidateTabs = selectedTabs.length ? selectedTabs : tabs;

    for (const tab of candidateTabs) {
      const record =
        this.extractAllowedRecord(tab) ||
        this.extractAllowedRecordFromTabs(tab.subtabs || []);

      if (record) {
        return record;
      }
    }

    return null;
  }

  extractAllowedRecord(source) {
    if (!source) {
      return null;
    }

    const pageReference = source.pageReference || source;
    const attributes = pageReference.attributes || {};
    const recordId = source.recordId || attributes.recordId;
    const objectApiName = source.objectApiName || attributes.objectApiName;

    if (
      recordId &&
      objectApiName &&
      this.allowedObjects.includes(objectApiName)
    ) {
      return { recordId, objectApiName };
    }

    return null;
  }

  setActiveRecord(nextRecord) {
    const nextRecordId = nextRecord?.recordId;
    const nextObjectApiName = nextRecord?.objectApiName;

    if (
      this.activeRecordId === nextRecordId &&
      this.activeObjectApiName === nextObjectApiName
    ) {
      this.announcePresence();
      return;
    }

    const previousRecordId = this.activeRecordId;
    const previousObjectApiName = this.activeObjectApiName;

    if (
      previousRecordId &&
      previousObjectApiName &&
      this.hasAnnouncedPresence
    ) {
      this.notifyServer("Left", previousRecordId, previousObjectApiName);
    }

    this.activeRecordId = nextRecordId;
    this.activeObjectApiName = nextObjectApiName;
    this.viewers = [];
    this.displayFields = [];
    this.hasAnnouncedPresence = false;

    if (this.activeRecordId) {
      this.lastEventSummary = "Detected focused record.";
    }

    this.announcePresence();
  }

  announcePresence() {
    if (
      !this.activeRecordId ||
      !this.activeObjectApiName ||
      !this.isSubscribed ||
      this.hasAnnouncedPresence
    ) {
      return;
    }

    this.hasAnnouncedPresence = true;
    this.notifyServer("Viewing");
  }

  leaveActiveRecord() {
    if (this.hasAnnouncedPresence) {
      this.notifyServer("Left");
      this.hasAnnouncedPresence = false;
    }
  }

  notifyServer(
    action,
    recordId = this.activeRecordId,
    objectApiName = this.activeObjectApiName
  ) {
    if (!recordId || !objectApiName) {
      return Promise.resolve();
    }

    this.lastEventSummary = `Publishing ${action}.`;
    console.log(
      `Record presence publishing ${action} for ${objectApiName} ${recordId}.`
    );

    return publishEvent({ recordId, objectApiName, action }).catch((error) => {
      this.lastEventSummary = `Could not publish ${action}. Check Apex/platform event permissions.`;
      console.error("Error publishing record presence event", error);
    });
  }

  handleSubscribe() {
    const messageCallback = (response) => {
      const eventPayload = response.data.payload;
      this.handlePresenceEvent(eventPayload);
    };

    subscribe(CHANNEL_NAME, -1, messageCallback)
      .then((response) => {
        this.subscription = response;
        this.isSubscribed = true;
        this.lastEventSummary = "Subscribed to record presence events.";
        this.announcePresence();
      })
      .catch((error) => {
        this.lastEventSummary =
          "Could not subscribe to record presence events.";
        console.error("Error subscribing to EMP API channel", error);
      });
  }

  handlePresenceEvent(eventPayload) {
    this.lastEventSummary = `Received ${eventPayload.UserAction__c || "unknown"} event.`;

    if (
      eventPayload.RecordId__c !== this.activeRecordId ||
      eventPayload.ObjectApiName__c !== this.activeObjectApiName ||
      eventPayload.UserId__c === USER_ID
    ) {
      return;
    }

    const user = {
      userId: eventPayload.UserId__c,
      name: eventPayload.UserName__c
    };
    const action = eventPayload.UserAction__c;

    if (action === "Viewing") {
      const isNewViewer = this.addViewer(user);

      if (isNewViewer) {
        this.showToast(user.name, "started viewing");
      }

      this.notifyServer("Present");
    } else if (action === "Present") {
      const isNewViewer = this.addViewer(user);

      if (isNewViewer) {
        this.showToast(user.name, "is also viewing");
      }
    } else if (action === "Left") {
      this.viewers = this.viewers.filter(
        (viewer) => viewer.userId !== user.userId
      );
    }
  }

  addViewer(user) {
    if (
      !user.userId ||
      this.viewers.some((viewer) => viewer.userId === user.userId)
    ) {
      return false;
    }

    this.viewers = [...this.viewers, user];
    return true;
  }

  handleUnsubscribe() {
    if (!this.subscription) {
      return;
    }

    unsubscribe(this.subscription, () => {
      console.log("Unsubscribed from record presence EMP API.");
    });

    this.subscription = undefined;
    this.isSubscribed = false;
  }

  registerErrorListener() {
    onError((error) => {
      this.lastEventSummary = "EMP API reported an error.";
      console.error("EMP API Error: ", JSON.stringify(error));
    });
  }

  showToast(userName, message) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Record Update",
        message: `${userName} ${message} this record.`,
        variant: "info"
      })
    );
  }

  parseCommaList(value) {
    return value
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean);
  }

  parseFieldConfig(value) {
    const config = new Map();

    value
      .split(";")
      .map((entry) => entry.trim())
      .filter(Boolean)
      .forEach((entry) => {
        const [objectApiName, fields] = entry.split("=");

        if (!objectApiName || !fields) {
          return;
        }

        config.set(
          objectApiName.trim(),
          fields
            .split(",")
            .map((field) =>
              this.normalizeFieldName(field.trim(), objectApiName.trim())
            )
            .filter(Boolean)
        );
      });

    return config;
  }

  normalizeFieldName(fieldName, objectApiName) {
    if (!fieldName) {
      return null;
    }

    const objectPrefix = `${objectApiName}.`;

    if (fieldName.startsWith(objectPrefix)) {
      return fieldName.slice(objectPrefix.length);
    }

    return fieldName.includes(".") ? null : fieldName;
  }

  getFieldKey(fieldName) {
    return fieldName.split(".").pop();
  }

  getFieldLabel(fieldName) {
    return fieldName
      .replace(/__c$/, "")
      .replace(/_/g, " ")
      .replace(/([a-z])([A-Z])/g, "$1 $2");
  }
}