'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Activity,
  ArrowUpRight,
  Check,
  ChevronRight,
  CircleDollarSign,
  Clock3,
  History,
  Info,
  RefreshCw,
  ShieldCheck,
  Terminal,
  Timer,
  Wallet,
  Zap,
} from 'lucide-react';
import {
  createWalletClient,
  custom,
  formatUnits,
  type Address,
} from 'viem';

import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import {
  collateralAbi,
  collateralAddress,
  contractsConfigured,
  marketAbi,
  marketAddress,
  monadTestnet,
  oracleAbi,
  publicClient,
} from '@/lib/contracts';

type EthereumProvider = {
  request: (args: { method: string; params?: unknown[] }) => Promise<unknown>;
  on?: (event: string, listener: (...args: unknown[]) => void) => void;
  removeListener?: (event: string, listener: (...args: unknown[]) => void) => void;
};

declare global {
  interface Window {
    ethereum?: EthereumProvider;
  }
}

type EpochView = {
  storedStatus: number;
  openedAt: bigint;
  tradingClose: bigint;
  expiry: bigint;
  settlementDeadline: bigint;
  reportPublishTime: bigint;
  strike: bigint;
  cap: bigint;
  maxPayout: bigint;
  pricingVolBps: number;
  jumpSizeBps: number;
  jumpWeightBps: number;
  feeBps: number;
  settlementPrice: bigint;
  payoutPerTicket: bigint;
  totalTickets: bigint;
  totalPaymentEscrow: bigint;
  totalProtocolFeeEscrow: bigint;
  totalPayoutLiability: bigint;
};

type QuoteView = {
  baseReference: bigint;
  jumpGuard: bigint;
  riskAdjusted: bigint;
  protocolFee: bigint;
  allIn: bigint;
  stressedPayoff: bigint;
};

type PositionView = {
  quantity: bigint;
  payment: bigint;
  closed: boolean;
};

type Snapshot = {
  epochId: bigint;
  status: number;
  epoch: EpochView;
  quote: QuoteView;
  totalPayment: bigint;
  totalMaxPayout: bigint;
  accounting: readonly [bigint, bigint, bigint, bigint, bigint, bigint, boolean];
  oraclePrice: bigint;
  oraclePublishTime: bigint;
  walletBalance: bigint;
  allowance: bigint;
  nextFaucetAt: bigint;
  faucetAmount: bigint;
  faucetCooldown: bigint;
  position: PositionView;
};

type OrderView = {
  id: string;
  epochId: bigint;
  quantity: bigint;
  payment: bigint;
  reserveAdded: bigint;
  status: number;
  epoch: EpochView;
  position: PositionView;
};

const STATUS_NAMES = [
  'Uninitialized',
  'Trading',
  'Locked',
  'Awaiting settlement',
  'Settled',
  'Cancelled',
];

const ZERO_POSITION: PositionView = {
  quantity: bigintValue(0),
  payment: bigintValue(0),
  closed: false,
};

function bigintValue(value: number | string) {
  return globalThis.BigInt(value);
}

function errorMessage(error: unknown) {
  if (error && typeof error === 'object') {
    const candidate = error as { shortMessage?: unknown; message?: unknown };
    if (typeof candidate.shortMessage === 'string') return candidate.shortMessage;
    if (typeof candidate.message === 'string') return candidate.message;
  }
  return 'Unexpected contract error.';
}

function decimal(value: bigint, decimals: number, digits = 4) {
  return Number(formatUnits(value, decimals)).toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: digits,
  });
}

function compactAddress(value: string) {
  return `${value.slice(0, 6)}…${value.slice(-4)}`;
}

function percentage(bps: number) {
  return `${(bps / 100).toFixed(2)}%`;
}

function countdown(expiry: bigint, now: number) {
  const remaining = Math.max(0, Number(expiry) - now);
  const minutes = Math.floor(remaining / 60);
  const seconds = remaining % 60;
  return `${minutes}m ${seconds.toString().padStart(2, '0')}s`;
}

function orderStatus(order: OrderView) {
  if (order.status === 4) return order.position.closed ? 'Claimed' : 'Claim ready';
  if (order.status === 5) return order.position.closed ? 'Refunded' : 'Refund ready';
  return STATUS_NAMES[order.status] ?? 'Unknown';
}

function orderStatusClass(order: OrderView) {
  if (order.status === 4 || order.status === 5) {
    return order.position.closed
      ? 'border-zinc-400/20 text-zinc-400'
      : 'border-[var(--signal)]/25 text-[var(--signal)]';
  }
  if (order.status === 1) return 'border-violet-400/25 text-violet-300';
  return 'border-amber-300/20 text-amber-200';
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-[10px] uppercase tracking-[0.08em] text-zinc-600">
        {label}
      </p>
      <p className="mt-1 font-mono text-sm font-semibold tabular-nums text-zinc-200">
        {value}
      </p>
    </div>
  );
}

function PayoffChart({
  strike,
  cap,
  spot,
  maxPayout,
}: {
  strike: bigint;
  cap: bigint;
  spot: bigint;
  maxPayout: bigint;
}) {
  const strikeNumber = Number(formatUnits(strike, 8));
  const capNumber = Number(formatUnits(cap, 8));
  const spotNumber = Number(formatUnits(spot, 8));
  const spread = capNumber - strikeNumber;
  const left = strikeNumber - spread * 0.8;
  const right = capNumber + spread * 0.8;
  const spotX = Math.max(42, Math.min(514, 42 + ((spotNumber - left) / (right - left)) * 472));

  return (
    <div className="overflow-hidden rounded-xl border border-white/[0.07] bg-black/20 px-3 pb-2 pt-3">
      <div className="mb-2 flex items-start justify-between">
        <div>
          <p className="text-xs font-medium text-zinc-300">Capped-call payoff</p>
          <p className="mt-0.5 text-[11px] text-zinc-500">
            Contract terms · {decimal(maxPayout, 6, 2)} mUSDC hard cap
          </p>
        </div>
        <Badge variant="outline" className="border-violet-400/20 text-violet-300">
          <Activity /> Supra spot ${decimal(spot, 8)}
        </Badge>
      </div>
      <svg className="block h-auto w-full" viewBox="0 0 540 246">
        <title>Live capped-call payoff from the active contract epoch</title>
        <defs>
          <linearGradient id="payoff-fill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#cbff5a" stopOpacity="0.23" />
            <stop offset="100%" stopColor="#cbff5a" stopOpacity="0" />
          </linearGradient>
        </defs>
        {[48, 88, 128, 168, 208].map((y) => (
          <line key={y} x1="42" x2="514" y1={y} y2={y} stroke="white" strokeOpacity="0.055" />
        ))}
        <line x1="42" x2="514" y1="208" y2="208" stroke="white" strokeOpacity="0.15" />
        <path d="M42 208 H214 L354 48 H514 V208 H42Z" fill="url(#payoff-fill)" />
        <path d="M42 208 H214 L354 48 H514" fill="none" stroke="#cbff5a" strokeWidth="3" />
        <line x1={spotX} x2={spotX} y1="36" y2="208" stroke="#a78bfa" strokeDasharray="4 5" />
        <circle cx={spotX} cy="118" r="5" fill="#a78bfa" stroke="#17131f" strokeWidth="3" />
        <text x="214" y="228" fill="#71717a" fontSize="11" textAnchor="middle">
          ${decimal(strike, 8)} strike
        </text>
        <text x="354" y="228" fill="#71717a" fontSize="11" textAnchor="middle">
          ${decimal(cap, 8)} cap
        </text>
        <text x="506" y="42" fill="#a1a1aa" fontSize="10" textAnchor="end">
          {decimal(maxPayout, 6, 2)} mUSDC
        </text>
      </svg>
    </div>
  );
}

export default function Home() {
  const [account, setAccount] = useState<Address>();
  const [quantity, setQuantity] = useState(1);
  const [snapshot, setSnapshot] = useState<Snapshot>();
  const [orders, setOrders] = useState<OrderView[]>([]);
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));
  const [loading, setLoading] = useState(false);
  const [ordersLoading, setOrdersLoading] = useState(false);
  const [readError, setReadError] = useState('');
  const [ordersError, setOrdersError] = useState('');
  const [transactionState, setTransactionState] = useState('');
  const [transactionError, setTransactionError] = useState('');
  const [transactionPending, setTransactionPending] = useState(false);

  const refresh = useCallback(async () => {
    if (!contractsConfigured || !marketAddress || !collateralAddress) return;
    setLoading(true);
    try {
      const epochId = (await publicClient.readContract({
        address: marketAddress,
        abi: marketAbi,
        functionName: 'activeEpochId',
      })) as bigint;
      if (epochId === bigintValue(0)) {
        setSnapshot(undefined);
        setReadError('Contracts are live, but the keeper has not opened the first epoch yet.');
        return;
      }

      const [epoch, status, quoteResult, accounting, oracleAddress, faucetAmount, faucetCooldown] =
        await Promise.all([
          publicClient.readContract({ address: marketAddress, abi: marketAbi, functionName: 'getEpoch', args: [epochId] }),
          publicClient.readContract({ address: marketAddress, abi: marketAbi, functionName: 'epochStatus', args: [epochId] }),
          publicClient.readContract({ address: marketAddress, abi: marketAbi, functionName: 'quote', args: [epochId, bigintValue(quantity)] }),
          publicClient.readContract({ address: marketAddress, abi: marketAbi, functionName: 'accounting' }),
          publicClient.readContract({ address: marketAddress, abi: marketAbi, functionName: 'oracle' }),
          publicClient.readContract({ address: collateralAddress, abi: collateralAbi, functionName: 'FAUCET_AMOUNT' }),
          publicClient.readContract({ address: collateralAddress, abi: collateralAbi, functionName: 'FAUCET_COOLDOWN' }),
        ]);

      const [oraclePrice, oraclePublishTime] = (await publicClient.readContract({
        address: oracleAddress as Address,
        abi: oracleAbi,
        functionName: 'latest',
      })) as readonly [bigint, bigint];

      let walletBalance = bigintValue(0);
      let allowance = bigintValue(0);
      let nextFaucetAt = bigintValue(0);
      let position = ZERO_POSITION;
      if (account) {
        [walletBalance, allowance, nextFaucetAt, position] = (await Promise.all([
          publicClient.readContract({ address: collateralAddress, abi: collateralAbi, functionName: 'balanceOf', args: [account] }),
          publicClient.readContract({ address: collateralAddress, abi: collateralAbi, functionName: 'allowance', args: [account, marketAddress] }),
          publicClient.readContract({ address: collateralAddress, abi: collateralAbi, functionName: 'nextFaucetAt', args: [account] }),
          publicClient.readContract({ address: marketAddress, abi: marketAbi, functionName: 'getPosition', args: [epochId, account] }),
        ])) as [bigint, bigint, bigint, PositionView];
      }

      const [quote, totalPayment, totalMaxPayout] = quoteResult as readonly [QuoteView, bigint, bigint];
      setSnapshot({
        epochId,
        status: Number(status),
        epoch: epoch as EpochView,
        quote,
        totalPayment,
        totalMaxPayout,
        accounting: accounting as Snapshot['accounting'],
        oraclePrice,
        oraclePublishTime,
        walletBalance,
        allowance,
        nextFaucetAt,
        faucetAmount: faucetAmount as bigint,
        faucetCooldown: faucetCooldown as bigint,
        position,
      });
      setReadError('');
    } catch (error) {
      setReadError(errorMessage(error));
    } finally {
      setLoading(false);
    }
  }, [account, quantity]);

  const refreshOrders = useCallback(async () => {
    if (!account || !contractsConfigured || !marketAddress) {
      setOrders([]);
      setOrdersError('');
      return;
    }
    const configuredMarket = marketAddress;

    setOrdersLoading(true);
    try {
      const activeEpochId = (await publicClient.readContract({
        address: configuredMarket,
        abi: marketAbi,
        functionName: 'activeEpochId',
      })) as bigint;
      const epochIds = Array.from(
        { length: Number(activeEpochId) },
        (_, index) => BigInt(index + 1),
      );
      const positions = (await Promise.all(
        epochIds.map((epochId) =>
          publicClient.readContract({
            address: configuredMarket,
            abi: marketAbi,
            functionName: 'getPosition',
            args: [epochId, account],
          }),
        ),
      )) as PositionView[];
      const ownedEpochs = epochIds.filter(
        (_, index) => positions[index].quantity > bigintValue(0),
      );

      const ownedOrders = await Promise.all(
        ownedEpochs.map(async (epochId) => {
          const position = positions[Number(epochId - bigintValue(1))];
          const [epoch, status] = await Promise.all([
            publicClient.readContract({
              address: configuredMarket,
              abi: marketAbi,
              functionName: 'getEpoch',
              args: [epochId],
            }),
            publicClient.readContract({
              address: configuredMarket,
              abi: marketAbi,
              functionName: 'epochStatus',
              args: [epochId],
            }),
          ]);
          const epochView = epoch as EpochView;
          return {
            id: `${account}-${epochId.toString()}`,
            epochId,
            quantity: position.quantity,
            payment: position.payment,
            reserveAdded: epochView.maxPayout * position.quantity,
            status: Number(status),
            epoch: epochView,
            position,
          };
        }),
      );

      setOrders(ownedOrders.sort((left, right) => (left.epochId > right.epochId ? -1 : 1)));
      setOrdersError('');
    } catch (error) {
      setOrdersError(errorMessage(error));
    } finally {
      setOrdersLoading(false);
    }
  }, [account]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1_000);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    const provider = window.ethereum;
    if (!provider) return;
    void provider.request({ method: 'eth_accounts' }).then((value) => {
      const first = (value as Address[])[0];
      if (first) setAccount(first);
    });
    const onAccounts = (...args: unknown[]) => setAccount((args[0] as Address[])[0]);
    const onChain = () => void refresh();
    provider.on?.('accountsChanged', onAccounts);
    provider.on?.('chainChanged', onChain);
    return () => {
      provider.removeListener?.('accountsChanged', onAccounts);
      provider.removeListener?.('chainChanged', onChain);
    };
  }, [refresh]);

  useEffect(() => {
    const initialRefresh = window.setTimeout(() => void refresh(), 0);
    if (!contractsConfigured || !marketAddress) {
      return () => window.clearTimeout(initialRefresh);
    }
    const unwatch = publicClient.watchContractEvent({
      address: marketAddress,
      abi: marketAbi,
      onLogs: (logs) => {
        void refresh();
        if (
          account &&
          logs.some((log) =>
            [
              'TicketsPurchased',
              'EpochSettled',
              'EpochCancelled',
              'Claimed',
              'Refunded',
            ].includes(log.eventName),
          )
        ) {
          void refreshOrders();
        }
      },
      onError: (error) => setReadError(error.message),
    });
    return () => {
      window.clearTimeout(initialRefresh);
      unwatch();
    };
  }, [account, refresh, refreshOrders]);

  useEffect(() => {
    const initialRefresh = window.setTimeout(() => void refreshOrders(), 0);
    return () => window.clearTimeout(initialRefresh);
  }, [refreshOrders]);

  const ensureWallet = useCallback(async () => {
    const provider = window.ethereum;
    if (!provider) throw new Error('No EVM browser wallet found.');
    try {
      await provider.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: '0x279f' }],
      });
    } catch {
      await provider.request({
        method: 'wallet_addEthereumChain',
        params: [
          {
            chainId: '0x279f',
            chainName: 'Monad Testnet',
            nativeCurrency: { name: 'Test MON', symbol: 'MON', decimals: 18 },
            rpcUrls: [monadTestnet.rpcUrls.default.http[0]],
            blockExplorerUrls: [monadTestnet.blockExplorers.default.url],
          },
        ],
      });
    }
    const accounts = (await provider.request({ method: 'eth_requestAccounts' })) as Address[];
    const selected = accounts[0];
    if (!selected) throw new Error('Wallet did not return an account.');
    setAccount(selected);
    return {
      selected,
      client: createWalletClient({
        account: selected,
        chain: monadTestnet,
        transport: custom(provider),
      }),
    };
  }, []);

  async function connectWallet() {
    setTransactionError('');
    try {
      await ensureWallet();
    } catch (error) {
      setTransactionError(error instanceof Error ? error.message : 'Wallet connection failed.');
    }
  }

  async function buy() {
    if (!snapshot || !marketAddress || !collateralAddress) return;
    setTransactionError('');
    setTransactionPending(true);
    try {
      const { selected, client } = await ensureWallet();
      const maxPremium =
        (snapshot.totalPayment * bigintValue(101) + bigintValue(99)) /
        bigintValue(100);
      if (snapshot.allowance < maxPremium) {
        setTransactionState('Approving mUSDC…');
        const approvalHash = await client.writeContract({
          address: collateralAddress,
          abi: collateralAbi,
          functionName: 'approve',
          args: [marketAddress, maxPremium],
          account: selected,
        });
        await publicClient.waitForTransactionReceipt({ hash: approvalHash });
      }

      setTransactionState('Reserving maximum payout and buying…');
      const purchaseHash = await client.writeContract({
        address: marketAddress,
        abi: marketAbi,
        functionName: 'buy',
        args: [snapshot.epochId, bigintValue(quantity), maxPremium],
        account: selected,
      });
      await publicClient.waitForTransactionReceipt({ hash: purchaseHash });
      setTransactionState('Purchase finalized on Monad Testnet');
      await Promise.all([refresh(), refreshOrders()]);
    } catch (error) {
      setTransactionState('');
      setTransactionError(errorMessage(error));
    } finally {
      setTransactionPending(false);
    }
  }

  async function closePosition(
    action: 'claim' | 'refund',
    epochId = snapshot?.epochId,
  ) {
    if (epochId === undefined || !marketAddress) return;
    setTransactionError('');
    setTransactionPending(true);
    try {
      const { selected, client } = await ensureWallet();
      setTransactionState(action === 'claim' ? 'Claiming payout…' : 'Claiming refund…');
      const hash = await client.writeContract({
        address: marketAddress,
        abi: marketAbi,
        functionName: action,
        args: [epochId],
        account: selected,
      });
      await publicClient.waitForTransactionReceipt({ hash });
      setTransactionState(action === 'claim' ? 'Payout claimed' : 'Refund claimed');
      await Promise.all([refresh(), refreshOrders()]);
    } catch (error) {
      setTransactionState('');
      setTransactionError(errorMessage(error));
    } finally {
      setTransactionPending(false);
    }
  }

  const accounting = snapshot?.accounting;
  const protectedTotal = useMemo(
    () =>
      accounting
        ? accounting[1] + accounting[2] + accounting[3] + accounting[4]
        : bigintValue(0),
    [accounting],
  );
  const statusName = snapshot ? STATUS_NAMES[snapshot.status] ?? 'Unknown' : 'Unavailable';
  const canBuy = Boolean(snapshot && snapshot.status === 1 && account && snapshot.walletBalance >= snapshot.totalPayment);
  const canClaim = Boolean(snapshot && snapshot.status === 4 && snapshot.position.quantity > bigintValue(0) && !snapshot.position.closed);
  const canRefund = Boolean(snapshot && snapshot.status === 5 && snapshot.position.quantity > bigintValue(0) && !snapshot.position.closed);
  const oracleAge = snapshot ? Math.max(0, now - Number(snapshot.oraclePublishTime)) : 0;
  const faucetReady = snapshot && (snapshot.nextFaucetAt === bigintValue(0) || bigintValue(now) >= snapshot.nextFaucetAt);

  return (
    <main className="relative min-h-screen overflow-hidden bg-[#09090c] text-zinc-100">
      <div className="risk-grid pointer-events-none fixed inset-0 opacity-35" aria-hidden="true" />
      <div className="relative mx-auto max-w-[1440px] px-4 pb-10 sm:px-6 lg:px-8">
        <header className="flex h-16 items-center justify-between border-b border-white/[0.07]">
          <div className="flex items-center gap-3">
            <div className="grid size-8 place-items-center rounded-lg border border-[var(--signal)]/25 bg-[var(--signal)]/10 text-[var(--signal)]">
              <Zap className="size-4" />
            </div>
            <div>
              <p className="font-heading text-base font-black uppercase tracking-[0.08em]">Schmeckles</p>
              <p className="text-[10px] uppercase tracking-[0.12em] text-zinc-600">Monad capped-call market</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Badge variant="outline" className="hidden border-violet-400/20 text-violet-300 sm:flex">
              <span className="size-1.5 rounded-full bg-violet-400" /> Monad Testnet
            </Badge>
            <Button variant="outline" size="sm" onClick={() => void connectWallet()}>
              <Wallet /> {account ? compactAddress(account) : 'Connect wallet'}
            </Button>
          </div>
        </header>

        {!contractsConfigured && (
          <div className="mt-5 rounded-xl border border-amber-400/20 bg-amber-400/[0.06] p-4 text-sm text-amber-100">
            Production contract addresses are not configured. Set `NEXT_PUBLIC_MARKET_ADDRESS` and `NEXT_PUBLIC_MUSDC_ADDRESS`; demo transactions and fabricated values are disabled.
          </div>
        )}
        {readError && (
          <div className="mt-5 rounded-xl border border-rose-400/20 bg-rose-400/[0.06] p-4 text-sm text-rose-200">
            {readError}
          </div>
        )}

        <section className="grid gap-4 pt-5 lg:grid-cols-[minmax(0,1.42fr)_minmax(360px,0.78fr)]">
          <div className="space-y-4">
            <Card className="border-white/[0.08] bg-[#111117]/95 shadow-2xl shadow-black/20">
              <CardHeader className="border-b border-white/[0.06] pb-4">
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div>
                    <div className="flex items-center gap-2">
                      <CardTitle className="font-heading text-2xl font-black uppercase tracking-tight">MON rises before expiry</CardTitle>
                      <Badge className={snapshot?.status === 1 ? 'bg-[var(--signal)]/10 text-[var(--signal)]' : 'bg-zinc-500/10 text-zinc-400'}>
                        {statusName}
                      </Badge>
                    </div>
                    <CardDescription className="mt-1">
                      Epoch #{snapshot?.epochId.toString() ?? '—'} · state read directly from Monad
                    </CardDescription>
                  </div>
                  <Button variant="ghost" size="sm" disabled={loading} onClick={() => void refresh()}>
                    <RefreshCw className={loading ? 'animate-spin' : ''} /> Refresh
                  </Button>
                </div>
              </CardHeader>
              <CardContent className="space-y-4 pt-4">
                {snapshot ? (
                  <>
                    <PayoffChart
                      strike={snapshot.epoch.strike}
                      cap={snapshot.epoch.cap}
                      spot={snapshot.oraclePrice}
                      maxPayout={snapshot.epoch.maxPayout}
                    />
                    <div className="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-7">
                      <div className="term-cell"><span>Strike</span><strong>${decimal(snapshot.epoch.strike, 8)}</strong><small>Supra at open</small></div>
                      <div className="term-cell"><span>Cap</span><strong>${decimal(snapshot.epoch.cap, 8)}</strong><small>{percentage(Number((snapshot.epoch.cap - snapshot.epoch.strike) * bigintValue(10_000) / snapshot.epoch.strike))} width</small></div>
                      <div className="term-cell"><span>Max payout</span><strong>{decimal(snapshot.epoch.maxPayout, 6, 2)}</strong><small>mUSDC / ticket</small></div>
                      <div className="term-cell"><span>Time left</span><strong>{countdown(snapshot.epoch.expiry, now)}</strong><small>5-minute epoch</small></div>
                      <div className="term-cell"><span>Volatility</span><strong>{percentage(snapshot.epoch.pricingVolBps)}</strong><small>annualized input</small></div>
                      <div className="term-cell"><span>Jump stress</span><strong>{percentage(snapshot.epoch.jumpSizeBps)}</strong><small>{percentage(snapshot.epoch.jumpWeightBps)} weight</small></div>
                      <div className="term-cell"><span>Protocol fee</span><strong>{percentage(snapshot.epoch.feeBps)}</strong><small>settled epochs</small></div>
                    </div>
                  </>
                ) : (
                  <div className="grid min-h-72 place-items-center rounded-xl border border-dashed border-white/10 text-sm text-zinc-500">
                    Waiting for an active onchain epoch.
                  </div>
                )}
              </CardContent>
            </Card>

            <Card className="border-white/[0.08] bg-[#111117]/95">
              <CardHeader className="pb-3">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <CardTitle className="flex items-center gap-2 text-sm">
                      <History className="size-4 text-violet-300" /> Your orders
                    </CardTitle>
                    <CardDescription className="mt-1">
                      Onchain positions · purchases in one epoch are combined
                    </CardDescription>
                  </div>
                  <Button
                    variant="ghost"
                    size="sm"
                    disabled={!account || ordersLoading}
                    onClick={() => void refreshOrders()}
                  >
                    <RefreshCw className={ordersLoading ? 'animate-spin' : ''} /> Refresh
                  </Button>
                </div>
              </CardHeader>
              <CardContent>
                {!account ? (
                  <div className="rounded-xl border border-dashed border-white/10 px-4 py-8 text-center text-sm text-zinc-500">
                    Connect a wallet to load its onchain order history.
                  </div>
                ) : ordersError ? (
                  <div className="rounded-xl border border-rose-400/20 bg-rose-400/[0.05] p-3 text-xs text-rose-200">
                    Order history could not be refreshed: {ordersError}
                  </div>
                ) : ordersLoading && orders.length === 0 ? (
                  <div className="rounded-xl border border-dashed border-white/10 px-4 py-8 text-center text-sm text-zinc-500">
                    Reading your purchase events…
                  </div>
                ) : orders.length === 0 ? (
                  <div className="rounded-xl border border-dashed border-white/10 px-4 py-8 text-center text-sm text-zinc-500">
                    No orders found for {compactAddress(account)}.
                  </div>
                ) : (
                  <div className="space-y-2">
                    {orders.map((order) => {
                      const resultLabel =
                        order.status === 4
                          ? 'Payout'
                          : order.status === 5
                            ? 'Refund'
                            : 'Max payout';
                      const resultAmount =
                        order.status === 4
                          ? order.epoch.payoutPerTicket * order.quantity
                          : order.status === 5
                            ? order.payment
                            : order.reserveAdded;
                      const canCloseOrder =
                        !order.position.closed &&
                        (order.status === 4 || order.status === 5);

                      return (
                        <div
                          key={order.id}
                          className="rounded-xl border border-white/[0.07] bg-black/20 p-3"
                        >
                          <div className="flex flex-wrap items-center justify-between gap-2">
                            <div className="flex items-center gap-2">
                              <span className="font-mono text-sm font-semibold text-zinc-200">
                                Epoch #{order.epochId.toString()}
                              </span>
                              <Badge
                                variant="outline"
                                className={orderStatusClass(order)}
                              >
                                {orderStatus(order)}
                              </Badge>
                            </div>
                            <span className="text-[11px] text-zinc-500">
                              Opened {new Date(Number(order.epoch.openedAt) * 1000).toLocaleString()}
                            </span>
                          </div>
                          <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-4">
                            <Metric label="Tickets" value={order.quantity.toString()} />
                            <Metric label="Premium paid" value={`${decimal(order.payment, 6)} mUSDC`} />
                            <Metric label="Strike" value={`$${decimal(order.epoch.strike, 8)}`} />
                            <Metric label={resultLabel} value={`${decimal(resultAmount, 6)} mUSDC`} />
                          </div>
                          {canCloseOrder && (
                            <Button
                              className="mt-3 w-full sm:w-auto"
                              variant="outline"
                              size="sm"
                              disabled={transactionPending}
                              onClick={() =>
                                void closePosition(
                                  order.status === 4 ? 'claim' : 'refund',
                                  order.epochId,
                                )
                              }
                            >
                              {order.status === 4 ? 'Claim epoch payout' : 'Claim epoch refund'}
                              <ArrowUpRight />
                            </Button>
                          )}
                        </div>
                      );
                    })}
                  </div>
                )}
              </CardContent>
            </Card>

            <Card className="border-white/[0.08] bg-[#111117]/95">
              <CardHeader className="pb-3">
                <div className="flex items-center justify-between">
                  <div>
                    <CardTitle className="flex items-center gap-2 text-sm"><ShieldCheck className="size-4 text-[var(--signal)]" /> Solvency monitor</CardTitle>
                    <CardDescription className="mt-1">Direct contract accounting · mUSDC</CardDescription>
                  </div>
                  <Badge variant="outline" className={accounting?.[6] ? 'border-[var(--signal)]/20 text-[var(--signal)]' : 'border-rose-400/20 text-rose-300'}>
                    {accounting?.[6] ? <Check /> : <Info />} {accounting?.[6] ? 'Solvent' : 'Unavailable'}
                  </Badge>
                </div>
              </CardHeader>
              <CardContent>
                <div className="grid gap-5 lg:grid-cols-[1.25fr_1fr]">
                  <div>
                    <div className="mb-2 flex justify-between text-[11px] text-zinc-500">
                      <span>Protected liabilities</span>
                      <span className="font-mono">{accounting ? decimal(protectedTotal, 6, 2) : '—'} / {accounting ? decimal(accounting[0], 6, 2) : '—'}</span>
                    </div>
                    <div className="flex h-3 overflow-hidden rounded-full bg-white/[0.045]">
                      {accounting && accounting[0] > bigintValue(0) && (
                        <>
                          <div className="bg-violet-400" style={{ width: `${Number(accounting[1] * bigintValue(10000) / accounting[0]) / 100}%` }} />
                          <div className="bg-sky-400" style={{ width: `${Number(accounting[2] * bigintValue(10000) / accounting[0]) / 100}%` }} />
                          <div className="bg-amber-300" style={{ width: `${Number(accounting[3] * bigintValue(10000) / accounting[0]) / 100}%` }} />
                          <div className="bg-zinc-500" style={{ width: `${Number(accounting[4] * bigintValue(10000) / accounting[0]) / 100}%` }} />
                        </>
                      )}
                    </div>
                    <p className="mt-3 font-mono text-[11px] text-zinc-500">C ≥ R + L + E + F · verified on every state transition</p>
                  </div>
                  <div className="grid grid-cols-3 gap-x-4 gap-y-3">
                    <Metric label="Collateral" value={accounting ? decimal(accounting[0], 6, 2) : '—'} />
                    <Metric label="Reserved" value={accounting ? decimal(accounting[1], 6, 2) : '—'} />
                    <Metric label="Claimable" value={accounting ? decimal(accounting[2], 6, 2) : '—'} />
                    <Metric label="Refundable" value={accounting ? decimal(accounting[3], 6, 2) : '—'} />
                    <Metric label="Fees" value={accounting ? decimal(accounting[4], 6, 2) : '—'} />
                    <Metric label="Free" value={accounting ? decimal(accounting[5], 6, 2) : '—'} />
                  </div>
                </div>
              </CardContent>
            </Card>
          </div>

          <div className="space-y-4">
            <Card className="border-white/[0.08] bg-[#111117]/95">
              <CardHeader className="pb-3">
                <CardTitle className="text-base">Buy capped-call tickets</CardTitle>
                <CardDescription>Every displayed amount comes from `quote()`.</CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="rounded-xl border border-white/[0.07] bg-black/20 p-3">
                  <div className="flex items-center justify-between">
                    <div><p className="text-[10px] uppercase tracking-[0.08em] text-zinc-600">Quantity</p><p className="mt-1 text-xs text-zinc-500">{snapshot ? `${decimal(snapshot.epoch.maxPayout, 6, 2)} mUSDC max each` : 'Awaiting epoch'}</p></div>
                    <div className="flex items-center gap-1 rounded-lg border border-white/[0.08] bg-white/[0.025] p-1">
                      <Button variant="ghost" size="icon-sm" onClick={() => setQuantity((value) => Math.max(1, value - 1))}>−</Button>
                      <span className="w-9 text-center font-mono text-sm font-semibold">{quantity}</span>
                      <Button variant="ghost" size="icon-sm" onClick={() => setQuantity((value) => Math.min(25, value + 1))}>+</Button>
                    </div>
                  </div>
                </div>

                <div className="space-y-2.5 rounded-xl border border-white/[0.07] bg-black/20 p-3 text-xs">
                  <div className="quote-row"><span>Black–Scholes call spread <Info /></span><strong>{snapshot ? decimal(snapshot.quote.baseReference * bigintValue(quantity), 6) : '—'}</strong></div>
                  <div className="quote-row"><span>Jump Guard</span><strong className="text-violet-300">{snapshot ? `+${decimal(snapshot.quote.jumpGuard * bigintValue(quantity), 6)}` : '—'}</strong></div>
                  <div className="quote-row"><span>Risk-adjusted price</span><strong>{snapshot ? decimal(snapshot.quote.riskAdjusted * bigintValue(quantity), 6) : '—'}</strong></div>
                  <div className="quote-row"><span>Protocol fee</span><strong>{snapshot ? decimal(snapshot.quote.protocolFee * bigintValue(quantity), 6) : '—'}</strong></div>
                  <div className="my-2 h-px bg-white/[0.07]" />
                  <div className="flex items-end justify-between"><span className="text-xs font-medium text-zinc-300">Total payment</span><span className="font-mono text-xl font-semibold text-white">{snapshot ? decimal(snapshot.totalPayment, 6) : '—'} <small className="text-[10px] font-medium text-zinc-500">mUSDC</small></span></div>
                </div>

                <div className="grid grid-cols-2 gap-2">
                  <div className="rounded-lg bg-white/[0.035] p-3"><span className="text-[10px] uppercase tracking-[0.08em] text-zinc-600">Wallet balance</span><p className="mt-1 font-mono text-sm font-semibold text-white">{account ? decimal(snapshot?.walletBalance ?? bigintValue(0), 6, 2) : '—'} mUSDC</p></div>
                  <div className="rounded-lg bg-white/[0.035] p-3"><span className="text-[10px] uppercase tracking-[0.08em] text-zinc-600">Max payout</span><p className="mt-1 font-mono text-sm font-semibold text-[var(--signal)]">{snapshot ? decimal(snapshot.totalMaxPayout, 6, 2) : '—'} mUSDC</p></div>
                </div>

                {snapshot && account && snapshot.walletBalance < snapshot.totalPayment && (
                  <div className="rounded-lg border border-amber-400/20 bg-amber-400/[0.05] p-3 text-[11px] leading-5 text-amber-100">
                    Insufficient mUSDC. Funding is CLI-only: run `./scripts/faucet.ps1`. It mints {decimal(snapshot.faucetAmount, 6, 2)} mUSDC per wallet every {Number(snapshot.faucetCooldown) / 3600} hours. {faucetReady ? 'This wallet is eligible now.' : `Next eligibility: ${new Date(Number(snapshot.nextFaucetAt) * 1000).toLocaleString()}.`}
                  </div>
                )}

                <Button className="w-full bg-[var(--signal)] text-[#111407] hover:bg-[#b9ec50]" disabled={!canBuy || transactionPending} onClick={() => void buy()}>
                  {account ? 'Approve & buy' : 'Connect wallet to buy'} <ChevronRight />
                </Button>
                {canClaim && <Button className="w-full" variant="outline" disabled={transactionPending} onClick={() => void closePosition('claim')}>Claim payout <ArrowUpRight /></Button>}
                {canRefund && <Button className="w-full" variant="outline" disabled={transactionPending} onClick={() => void closePosition('refund')}>Claim refund <ArrowUpRight /></Button>}
                {transactionState && <p className="text-center text-xs text-[var(--signal)]"><Check className="mr-1 inline size-3.5" /> {transactionState}</p>}
                {transactionError && <p className="text-center text-xs text-rose-300">{transactionError}</p>}
              </CardContent>
            </Card>

            <Card className="border-white/[0.08] bg-[#111117]/95">
              <CardHeader className="pb-3"><CardTitle className="text-sm">Live infrastructure</CardTitle></CardHeader>
              <CardContent className="space-y-3 text-xs">
                <div className="flex items-center justify-between"><span className="flex items-center gap-2 text-zinc-500"><Activity className="size-3.5" /> Supra MON/USD</span><span className="font-mono text-zinc-300">{snapshot ? `$${decimal(snapshot.oraclePrice, 8)}` : '—'}</span></div>
                <div className="flex items-center justify-between"><span className="flex items-center gap-2 text-zinc-500"><Clock3 className="size-3.5" /> Observation age</span><span className={oracleAge <= 60 ? 'font-mono text-[var(--signal)]' : 'font-mono text-rose-300'}>{snapshot ? `${oracleAge}s` : '—'}</span></div>
                <div className="flex items-center justify-between"><span className="flex items-center gap-2 text-zinc-500"><CircleDollarSign className="size-3.5" /> Position</span><span className="font-mono text-zinc-300">{snapshot ? snapshot.position.quantity.toString() : '—'} tickets</span></div>
                <div className="flex items-center justify-between"><span className="flex items-center gap-2 text-zinc-500"><Timer className="size-3.5" /> Settlement deadline</span><span className="font-mono text-zinc-300">{snapshot ? new Date(Number(snapshot.epoch.settlementDeadline) * 1000).toLocaleTimeString() : '—'}</span></div>
                <div className="flex items-center justify-between"><span className="flex items-center gap-2 text-zinc-500"><Terminal className="size-3.5" /> Faucet</span><span className="text-zinc-300">CLI only</span></div>
              </CardContent>
            </Card>
          </div>
        </section>

        <footer className="mt-5 flex flex-wrap items-center justify-between gap-3 border-t border-white/[0.06] pt-5 text-[10px] uppercase tracking-[0.09em] text-zinc-600">
          <span>Monad Testnet · verified Supra settlement · test collateral only</span>
          <a className="flex items-center gap-1 text-zinc-500 hover:text-zinc-300" href={marketAddress ? `${monadTestnet.blockExplorers.default.url}/address/${marketAddress}` : monadTestnet.blockExplorers.default.url} target="_blank" rel="noreferrer">View contract <ArrowUpRight className="size-3" /></a>
        </footer>
      </div>
    </main>
  );
}
