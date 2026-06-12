import { LightningElement, api, wire } from 'lwc';
import getFederatedData from '@salesforce/apex/AetherFederatedController.getFederatedData';

const CURRENCY_FORMATTER = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0
});

const DATE_FORMATTER = new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric'
});

export default class AetherFederated360 extends LightningElement {
    @api recordId;

    data;
    errorMessage;
    isLoading = true;

    @wire(getFederatedData, { accountId: '$recordId' })
    wiredFederatedData({ data, error }) {
        this.isLoading = false;

        if (data) {
            this.data = data;
            this.errorMessage = undefined;
            return;
        }

        this.data = undefined;
        this.errorMessage = this.reduceError(error);
    }

    get hasWarnings() {
        return this.data?.warnings?.length > 0;
    }

    get healthScoreClass() {
        const baseClass = 'health-score';
        switch (this.data?.healthScore) {
            case 'Strong':
                return `${baseClass} is-strong`;
            case 'Watch':
                return `${baseClass} is-watch`;
            default:
                return `${baseClass} is-risk`;
        }
    }

    get formattedOpenPipeline() {
        const amount = this.data?.crm?.openPipeline ?? 0;
        return CURRENCY_FORMATTER.format(amount);
    }

    get formattedLastActivity() {
        const value = this.data?.crm?.lastActivityDate;
        if (!value) {
            return 'No recent activity';
        }

        return DATE_FORMATTER.format(new Date(value));
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error';
        }

        if (Array.isArray(error.body)) {
            return error.body.map((item) => item.message).join(', ');
        }

        return error.body?.message || error.message || 'Unknown error';
    }
}
