using Microsoft.AspNetCore.Mvc;
using SolidarityGrid.Node.Models;
using SolidarityGrid.Node.Services;

namespace SolidarityGrid.Node.Controllers;

[ApiController]
public class PaymentController : ControllerBase
{
    private readonly NodeState _state;
    private readonly GossipService _gossip;
    private readonly ILogger<PaymentController> _logger;

    public PaymentController(NodeState state, GossipService gossip, ILogger<PaymentController> logger)
    {
        _state = state;
        _gossip = gossip;
        _logger = logger;
    }

    [HttpPost("pay")]
    public async Task<IActionResult> Pay([FromBody] PaymentRequest request)
    {
        var delay = Random.Shared.Next(5000, 10001);

        var tx = new Transaction
        {
            Amount = request.Amount,
            Currency = request.Currency,
            TotalDelayMs = delay,
            OwnerNodeId = _state.NodeId,
            State = TransactionState.Processing,
            ProcessingStartedAt = DateTime.UtcNow
        };

        _state.Transactions[tx.Id] = tx;

        _logger.LogInformation("[{NodeId}] 💰 New payment ${Amount} {Currency}. Transaction {TxId} created. Processing in ~{Delay}ms.",
            _state.NodeId, tx.Amount, tx.Currency, tx.Id, tx.TotalDelayMs);

        await _gossip.BroadcastImmediate(tx);

        _logger.LogInformation("[{NodeId}] 🔄 Broadcast {TxId} to peers. Starting background processing...",
            _state.NodeId, tx.Id);

        _ = ProcessTransactionAsync(tx);

        return Accepted(new PaymentResponse
        {
            TransactionId = tx.Id,
            Status = "processing",
            Node = _state.NodeId,
            EstimatedDelayMs = tx.TotalDelayMs
        });
    }

    private async Task ProcessTransactionAsync(Transaction tx)
    {
        try
        {
            var elapsed = 0;
            var interval = 1000;

            while (elapsed < tx.TotalDelayMs)
            {
                await Task.Delay(interval);
                elapsed += interval;
            }

            if (_state.Transactions.TryGetValue(tx.Id, out var current) &&
                current.State == TransactionState.Processing &&
                current.OwnerNodeId == _state.NodeId)
            {
                tx.State = TransactionState.Completed;
                tx.CompletedAt = DateTime.UtcNow;
                _state.Transactions[tx.Id] = tx;

                _logger.LogInformation("[{NodeId}] ✓ Transaction {TxId} completed successfully after {Delay}ms.",
                    _state.NodeId, tx.Id, tx.TotalDelayMs);

                await _gossip.BroadcastImmediate(tx);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError("[{NodeId}] ✗ Transaction {TxId} failed: {Message}", _state.NodeId, tx.Id, ex.Message);
            tx.State = TransactionState.Failed;
            _state.Transactions[tx.Id] = tx;
        }
    }

    [HttpGet("transactions")]
    public IActionResult GetTransactions()
    {
        return Ok(_state.Transactions.Values.OrderBy(t => t.CreatedAt).ToList());
    }

    [HttpGet("transactions/{id}")]
    public IActionResult GetTransaction(string id)
    {
        if (_state.Transactions.TryGetValue(id.ToUpper(), out var tx))
            return Ok(tx);
        return NotFound();
    }
}
