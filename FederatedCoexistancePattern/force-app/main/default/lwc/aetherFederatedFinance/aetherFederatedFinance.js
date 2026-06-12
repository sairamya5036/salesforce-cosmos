import { LightningElement, api } from 'lwc';

const CURRENCY_FORMATTER = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0
});

export default class AetherFederatedFinance extends LightningElement {
    @api data;

    get formattedCreditLimit() {
        return CURRENCY_FORMATTER.format(this.data?.creditLimit ?? 0);
    }

    get formattedBalanceDue() {
        return CURRENCY_FORMATTER.format(this.data?.balanceDue ?? 0);
    }

    get formattedDso() {
        const dso = this.data?.dso;
        return dso === null || dso === undefined ? 'Not available' : `${dso} days`;
    }
}
