namespace SolidarityGrid.Node.Models;

public enum TransactionState
{
    Pending,
    Processing,
    Completed,
    Failed
}

public class Transaction
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N")[..8].ToUpper();
    public string? OwnerNodeId { get; set; }
    public TransactionState State { get; set; } = TransactionState.Pending;
    public decimal Amount { get; set; }
    public string Currency { get; set; } = "USD";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? ProcessingStartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }
    public int TotalDelayMs { get; set; }
}
