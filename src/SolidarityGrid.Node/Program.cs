using SolidarityGrid.Node.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddSingleton<NodeState>();
builder.Services.AddSingleton<HeartbeatService>();
builder.Services.AddSingleton<GossipService>();
builder.Services.AddSingleton<RecoveryService>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<HeartbeatService>());
builder.Services.AddHostedService(sp => sp.GetRequiredService<GossipService>());
builder.Services.AddHostedService(sp => sp.GetRequiredService<RecoveryService>());

var app = builder.Build();
app.MapControllers();

var state = app.Services.GetRequiredService<NodeState>();
var logger = app.Services.GetRequiredService<ILogger<Program>>();
logger.LogInformation("=== SolidarityGrid Node [{NodeId}] starting up ===", state.NodeId);
logger.LogInformation("Peers: {Peers}", string.Join(", ", state.PeerUrls));

app.Run();
