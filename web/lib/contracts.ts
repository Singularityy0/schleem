import { createPublicClient, defineChain, http, isAddress, zeroAddress } from 'viem';

export const monadTestnet = defineChain({
  id: 10_143,
  name: 'Monad Testnet',
  nativeCurrency: { name: 'Test MON', symbol: 'MON', decimals: 18 },
  rpcUrls: {
    default: {
      http: [
        process.env.NEXT_PUBLIC_MONAD_RPC_URL ??
          'https://testnet-rpc.monad.xyz',
      ],
    },
  },
  blockExplorers: {
    default: {
      name: 'MonadVision Testnet',
      url: 'https://testnet.monadvision.com',
    },
  },
  testnet: true,
});

const marketValue = process.env.NEXT_PUBLIC_MARKET_ADDRESS ?? '';
const collateralValue = process.env.NEXT_PUBLIC_MUSDC_ADDRESS ?? '';

export const marketAddress = isAddress(marketValue) ? marketValue : undefined;
export const collateralAddress = isAddress(collateralValue)
  ? collateralValue
  : undefined;

export const contractsConfigured = Boolean(
  marketAddress &&
    collateralAddress &&
    marketAddress !== zeroAddress &&
    collateralAddress !== zeroAddress,
);

export const publicClient = createPublicClient({
  chain: monadTestnet,
  transport: http(),
  pollingInterval: 1_500,
});

export const marketAbi = [
  {
    type: 'function',
    name: 'activeEpochId',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'oracle',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
  },
  {
    type: 'function',
    name: 'epochStatus',
    stateMutability: 'view',
    inputs: [{ name: 'epochId', type: 'uint256' }],
    outputs: [{ name: '', type: 'uint8' }],
  },
  {
    type: 'function',
    name: 'getEpoch',
    stateMutability: 'view',
    inputs: [{ name: 'epochId', type: 'uint256' }],
    outputs: [
      {
        name: '',
        type: 'tuple',
        components: [
          { name: 'storedStatus', type: 'uint8' },
          { name: 'openedAt', type: 'uint64' },
          { name: 'tradingClose', type: 'uint64' },
          { name: 'expiry', type: 'uint64' },
          { name: 'settlementDeadline', type: 'uint64' },
          { name: 'reportPublishTime', type: 'uint64' },
          { name: 'strike', type: 'uint256' },
          { name: 'cap', type: 'uint256' },
          { name: 'maxPayout', type: 'uint256' },
          { name: 'pricingVolBps', type: 'uint32' },
          { name: 'jumpSizeBps', type: 'uint16' },
          { name: 'jumpWeightBps', type: 'uint16' },
          { name: 'feeBps', type: 'uint16' },
          { name: 'settlementPrice', type: 'uint256' },
          { name: 'payoutPerTicket', type: 'uint256' },
          { name: 'totalTickets', type: 'uint256' },
          { name: 'totalPaymentEscrow', type: 'uint256' },
          { name: 'totalProtocolFeeEscrow', type: 'uint256' },
          { name: 'totalPayoutLiability', type: 'uint256' },
        ],
      },
    ],
  },
  {
    type: 'function',
    name: 'getPosition',
    stateMutability: 'view',
    inputs: [
      { name: 'epochId', type: 'uint256' },
      { name: 'account', type: 'address' },
    ],
    outputs: [
      {
        name: '',
        type: 'tuple',
        components: [
          { name: 'quantity', type: 'uint256' },
          { name: 'payment', type: 'uint256' },
          { name: 'closed', type: 'bool' },
        ],
      },
    ],
  },
  {
    type: 'function',
    name: 'quote',
    stateMutability: 'view',
    inputs: [
      { name: 'epochId', type: 'uint256' },
      { name: 'quantity', type: 'uint256' },
    ],
    outputs: [
      {
        name: 'perTicket',
        type: 'tuple',
        components: [
          { name: 'baseReference', type: 'uint256' },
          { name: 'jumpGuard', type: 'uint256' },
          { name: 'riskAdjusted', type: 'uint256' },
          { name: 'protocolFee', type: 'uint256' },
          { name: 'allIn', type: 'uint256' },
          { name: 'stressedPayoff', type: 'uint256' },
        ],
      },
      { name: 'totalPayment', type: 'uint256' },
      { name: 'totalMaxPayout', type: 'uint256' },
    ],
  },
  {
    type: 'function',
    name: 'accounting',
    stateMutability: 'view',
    inputs: [],
    outputs: [
      { name: 'balance', type: 'uint256' },
      { name: 'reserved', type: 'uint256' },
      { name: 'claimable', type: 'uint256' },
      { name: 'refundable', type: 'uint256' },
      { name: 'fees', type: 'uint256' },
      { name: 'free', type: 'uint256' },
      { name: 'solvent', type: 'bool' },
    ],
  },
  {
    type: 'function',
    name: 'buy',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'epochId', type: 'uint256' },
      { name: 'quantity', type: 'uint256' },
      { name: 'maxPremium', type: 'uint256' },
    ],
    outputs: [{ name: 'payment', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'claim',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'epochId', type: 'uint256' }],
    outputs: [{ name: 'amount', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'refund',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'epochId', type: 'uint256' }],
    outputs: [{ name: 'amount', type: 'uint256' }],
  },
  {
    type: 'event',
    name: 'LivePriceUpdated',
    inputs: [
      { indexed: false, name: 'price', type: 'uint256' },
      { indexed: false, name: 'publishTime', type: 'uint64' },
    ],
  },
  {
    type: 'event',
    name: 'EpochOpened',
    inputs: [
      { indexed: true, name: 'epochId', type: 'uint256' },
      { indexed: false, name: 'strike', type: 'uint256' },
      { indexed: false, name: 'cap', type: 'uint256' },
      { indexed: false, name: 'expiry', type: 'uint64' },
      { indexed: false, name: 'maxPayout', type: 'uint256' },
    ],
  },
  {
    type: 'event',
    name: 'TicketsPurchased',
    inputs: [
      { indexed: true, name: 'epochId', type: 'uint256' },
      { indexed: true, name: 'buyer', type: 'address' },
      { indexed: false, name: 'quantity', type: 'uint256' },
      { indexed: false, name: 'payment', type: 'uint256' },
      { indexed: false, name: 'reserveAdded', type: 'uint256' },
      { indexed: false, name: 'observedPrice', type: 'uint256' },
    ],
  },
  {
    type: 'event',
    name: 'EpochSettled',
    inputs: [
      { indexed: true, name: 'epochId', type: 'uint256' },
      { indexed: false, name: 'settlementPrice', type: 'uint256' },
      { indexed: false, name: 'reportPublishTime', type: 'uint64' },
      { indexed: false, name: 'payoutPerTicket', type: 'uint256' },
      { indexed: false, name: 'aggregatePayout', type: 'uint256' },
    ],
  },
  {
    type: 'event',
    name: 'EpochCancelled',
    inputs: [
      { indexed: true, name: 'epochId', type: 'uint256' },
      { indexed: false, name: 'reserveReleased', type: 'uint256' },
    ],
  },
  {
    type: 'event',
    name: 'Claimed',
    inputs: [
      { indexed: true, name: 'epochId', type: 'uint256' },
      { indexed: true, name: 'user', type: 'address' },
      { indexed: false, name: 'amount', type: 'uint256' },
    ],
  },
  {
    type: 'event',
    name: 'Refunded',
    inputs: [
      { indexed: true, name: 'epochId', type: 'uint256' },
      { indexed: true, name: 'user', type: 'address' },
      { indexed: false, name: 'amount', type: 'uint256' },
    ],
  },
] as const;

export const collateralAbi = [
  {
    type: 'function',
    name: 'FAUCET_AMOUNT',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'FAUCET_COOLDOWN',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint64' }],
  },
  {
    type: 'function',
    name: 'balanceOf',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'allowance',
    stateMutability: 'view',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    type: 'function',
    name: 'approve',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    type: 'function',
    name: 'nextFaucetAt',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint64' }],
  },
] as const;

export const oracleAbi = [
  {
    type: 'function',
    name: 'latest',
    stateMutability: 'view',
    inputs: [],
    outputs: [
      { name: 'price', type: 'uint256' },
      { name: 'publishTime', type: 'uint64' },
    ],
  },
] as const;
