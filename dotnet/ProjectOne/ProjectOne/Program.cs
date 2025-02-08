using ProjectOne.Data;
using ProjectOne.Services;
using Microsoft.Extensions.Logging;
using ProjectOne.Interfaces; // Add this line

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllers();

builder.Services.AddDbContext<ProjectContext>();

// Register ProjectService with the dependency injection container
builder.Services.AddScoped<IProjectService, ProjectService>();

// Add logging service
builder.Services.AddLogging(); // Add this line

// Add OpenAPI/Swagger document
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseAuthorization();

app.MapControllers();

app.Run();
