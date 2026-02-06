"use client";

import { useState, useEffect } from "react";
import { Address } from "@scaffold-ui/components";
import type { NextPage } from "next";
import { formatUnits, parseUnits } from "viem";
import { useAccount } from "wagmi";
import {
  useScaffoldReadContract,
  useScaffoldWriteContract,
  useScaffoldEventHistory,
} from "~~/hooks/scaffold-eth";

const CLAWD_TOKEN = "0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07";
const VOTE_ADDRESS = "0xf86D964188115AFc8DBB54d088164f624B916442";

const formatClawd = (value: bigint | undefined): string => {
  if (!value) return "0";
  const num = parseFloat(formatUnits(value, 18));
  if (num >= 1_000_000) return `${(num / 1_000_000).toFixed(2)}M`;
  if (num >= 1_000) return `${(num / 1_000).toFixed(1)}K`;
  return num.toFixed(0);
};

const timeAgo = (ts: number): string => {
  const diff = Math.floor(Date.now() / 1000) - ts;
  if (diff < 60) return "just now";
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  return `${Math.floor(diff / 86400)}d ago`;
};

const Home: NextPage = () => {
  const { address } = useAccount();
  const [showCreate, setShowCreate] = useState(false);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [voteAmounts, setVoteAmounts] = useState<Record<number, string>>({});
  const [isCreating, setIsCreating] = useState(false);
  const [isApproving, setIsApproving] = useState(false);
  const [votingId, setVotingId] = useState<number | null>(null);
  const [unvotingId, setUnvotingId] = useState<number | null>(null);
  const [clawdPrice, setClawdPrice] = useState(0);

  const { data: proposalCost } = useScaffoldReadContract({ contractName: "CLAWDVote", functionName: "proposalCost" });
  const { data: minVoteAmount } = useScaffoldReadContract({ contractName: "CLAWDVote", functionName: "minVoteAmount" });
  const { data: nextProposalId } = useScaffoldReadContract({ contractName: "CLAWDVote", functionName: "nextProposalId" });
  const { data: totalBurned } = useScaffoldReadContract({ contractName: "CLAWDVote", functionName: "totalBurned" });
  const { data: clawdBalance } = useScaffoldReadContract({ contractName: "CLAWD", functionName: "balanceOf", args: [address] });
  const { data: allowance } = useScaffoldReadContract({ contractName: "CLAWD", functionName: "allowance", args: [address, VOTE_ADDRESS] });

  const { writeContractAsync: writeVote } = useScaffoldWriteContract("CLAWDVote");
  const { writeContractAsync: writeClawd } = useScaffoldWriteContract("CLAWD");

  const { data: createEvents } = useScaffoldEventHistory({
    contractName: "CLAWDVote", eventName: "ProposalCreated", fromBlock: 0n, watch: true,
  });
  const { data: voteEvents } = useScaffoldEventHistory({
    contractName: "CLAWDVote", eventName: "Voted", fromBlock: 0n, watch: true,
  });

  useEffect(() => {
    const f = async () => {
      try {
        const r = await fetch(`https://api.dexscreener.com/latest/dex/tokens/${CLAWD_TOKEN}`);
        const d = await r.json();
        if (d.pairs?.[0]) setClawdPrice(parseFloat(d.pairs[0].priceUsd || "0"));
      } catch {}
    };
    f();
    const i = setInterval(f, 60000);
    return () => clearInterval(i);
  }, []);

  const needsApproval = (amount: bigint) => !allowance || allowance < amount;
  const toUsd = (v: bigint | undefined) => {
    if (!v || !clawdPrice) return "";
    const usd = parseFloat(formatUnits(v, 18)) * clawdPrice;
    return usd < 0.01 ? "< $0.01" : `~$${usd.toFixed(2)}`;
  };

  // Build proposal list from events
  const proposals = (createEvents || [])
    .map(e => ({
      id: Number(e.args.id || 0),
      creator: e.args.creator,
      title: e.args.title || "",
      description: e.args.description || "",
      totalStaked: 0n,
      voterCount: 0,
    }))
    .sort((a, b) => b.id - a.id);

  // Aggregate votes per proposal
  const voteTotals: Record<number, bigint> = {};
  (voteEvents || []).forEach(e => {
    const pid = Number(e.args.proposalId || 0);
    voteTotals[pid] = (voteTotals[pid] || 0n) + (e.args.amount || 0n);
  });

  const handleApprove = async (amount: bigint) => {
    setIsApproving(true);
    try {
      await writeClawd({ functionName: "approve", args: [VOTE_ADDRESS, amount * 100n] });
    } catch (e) { console.error(e); }
    finally { setIsApproving(false); }
  };

  const handleCreate = async () => {
    if (!title.trim()) return;
    setIsCreating(true);
    try {
      await writeVote({ functionName: "createProposal", args: [title.trim(), description.trim()] });
      setTitle(""); setDescription(""); setShowCreate(false);
    } catch (e) { console.error(e); }
    finally { setIsCreating(false); }
  };

  const handleVote = async (proposalId: number) => {
    const amt = voteAmounts[proposalId];
    if (!amt || parseFloat(amt) <= 0) return;
    setVotingId(proposalId);
    try {
      await writeVote({ functionName: "vote", args: [BigInt(proposalId), parseUnits(amt, 18)] });
      setVoteAmounts(prev => ({ ...prev, [proposalId]: "" }));
    } catch (e) { console.error(e); }
    finally { setVotingId(null); }
  };

  const handleUnvote = async (proposalId: number) => {
    setUnvotingId(proposalId);
    try {
      await writeVote({ functionName: "unvote", args: [BigInt(proposalId)] });
    } catch (e) { console.error(e); }
    finally { setUnvotingId(null); }
  };

  return (
    <div className="flex flex-col items-center grow pt-6 px-4 pb-12">
      <div className="w-full max-w-3xl">

        {/* Stats */}
        <div className="flex justify-between items-center mb-6 text-sm opacity-60">
          <div className="flex gap-4">
            <span>📋 {nextProposalId?.toString() || "0"} proposals</span>
            <span>🔥 {formatClawd(totalBurned)} CLAWD burned</span>
            {totalBurned && clawdPrice > 0 && <span>({toUsd(totalBurned)})</span>}
          </div>
          {address && <span>Balance: {formatClawd(clawdBalance)}</span>}
        </div>

        {/* Create button */}
        {address && !showCreate && (
          <button className="btn btn-primary w-full mb-6" onClick={() => setShowCreate(true)}>
            + Create Proposal ({formatClawd(proposalCost)} CLAWD)
          </button>
        )}

        {/* Create form */}
        {showCreate && (
          <div className="bg-base-200 rounded-2xl p-6 mb-6">
            <h2 className="text-lg font-bold mb-4">New Proposal</h2>
            <input
              className="input input-bordered w-full mb-3"
              placeholder="Title (max 100 chars)"
              value={title}
              onChange={e => setTitle(e.target.value)}
              maxLength={100}
              disabled={isCreating || isApproving}
            />
            <textarea
              className="textarea textarea-bordered w-full mb-3"
              placeholder="Description (optional, max 500 chars)"
              value={description}
              onChange={e => setDescription(e.target.value)}
              maxLength={500}
              rows={3}
              disabled={isCreating || isApproving}
            />
            <div className="flex gap-2">
              {proposalCost && needsApproval(proposalCost) ? (
                <button className="btn btn-primary flex-1" disabled={isApproving} onClick={() => proposalCost && handleApprove(proposalCost)}>
                  {isApproving ? <><span className="loading loading-spinner loading-xs" /> Approving...</> : "Approve CLAWD"}
                </button>
              ) : (
                <button className="btn btn-primary flex-1" disabled={isCreating || !title.trim()} onClick={handleCreate}>
                  {isCreating ? <><span className="loading loading-spinner loading-xs" /> Creating...</> : `Create (burns ${formatClawd(proposalCost)})`}
                </button>
              )}
              <button className="btn btn-ghost" onClick={() => setShowCreate(false)}>Cancel</button>
            </div>
          </div>
        )}

        {/* Proposals */}
        {proposals.length === 0 ? (
          <div className="bg-base-200 rounded-2xl p-12 text-center opacity-40">
            <p className="text-4xl mb-2">🗳️</p>
            <p>No proposals yet. Be the first!</p>
            <p className="text-sm mt-1">Cost: {formatClawd(proposalCost)} CLAWD (burned)</p>
          </div>
        ) : (
          <div className="space-y-4">
            {proposals.map(p => {
              const staked = voteTotals[p.id] || 0n;
              const voteAmt = voteAmounts[p.id] || "";
              const voteAmtBigInt = voteAmt ? parseUnits(voteAmt || "0", 18) : 0n;

              return (
                <div key={p.id} className="bg-base-200 rounded-2xl p-5">
                  <div className="flex justify-between items-start mb-2">
                    <div>
                      <h3 className="font-bold text-lg">{p.title}</h3>
                      {p.description && <p className="text-sm opacity-60 mt-1">{p.description}</p>}
                    </div>
                    <span className="badge badge-ghost">#{p.id}</span>
                  </div>

                  <div className="flex items-center gap-2 text-sm opacity-60 mb-3">
                    <span>by</span> <Address address={p.creator} />
                  </div>

                  {/* Stake bar */}
                  <div className="flex items-center justify-between mb-3">
                    <div>
                      <span className="text-2xl font-bold text-primary">{formatClawd(staked)}</span>
                      <span className="text-sm opacity-60 ml-2">CLAWD staked</span>
                      {staked > 0n && clawdPrice > 0 && (
                        <span className="text-xs opacity-40 ml-2">({toUsd(staked)})</span>
                      )}
                    </div>
                  </div>

                  {/* Vote controls */}
                  {address && (
                    <div className="flex gap-2 items-center">
                      <input
                        className="input input-bordered input-sm flex-1"
                        type="number"
                        placeholder={`Min ${formatClawd(minVoteAmount)}`}
                        value={voteAmt}
                        onChange={e => setVoteAmounts(prev => ({ ...prev, [p.id]: e.target.value }))}
                        disabled={votingId === p.id}
                      />
                      {voteAmtBigInt > 0n && needsApproval(voteAmtBigInt) ? (
                        <button className="btn btn-primary btn-sm" disabled={isApproving} onClick={() => handleApprove(voteAmtBigInt)}>
                          {isApproving ? "Approving..." : "Approve"}
                        </button>
                      ) : (
                        <button
                          className="btn btn-primary btn-sm"
                          disabled={votingId === p.id || !voteAmt || parseFloat(voteAmt) <= 0}
                          onClick={() => handleVote(p.id)}
                        >
                          {votingId === p.id ? <><span className="loading loading-spinner loading-xs" /> Voting...</> : "Vote"}
                        </button>
                      )}
                      <button
                        className="btn btn-ghost btn-sm"
                        disabled={unvotingId === p.id}
                        onClick={() => handleUnvote(p.id)}
                      >
                        {unvotingId === p.id ? "..." : "Unstake"}
                      </button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}

        {!address && (
          <p className="text-center text-sm opacity-60 mt-6">Connect wallet to create proposals and vote</p>
        )}
      </div>
    </div>
  );
};

export default Home;
