using Microsoft.EntityFrameworkCore;
using ProjectOne.Models;
using System.Collections.Generic;

namespace ProjectOne.Data
{
    public class ProjectContext : DbContext
    {
        public DbSet<Project> Projects { get; set; }

        public string DbPath { get; private set; }

        public ProjectContext(DbContextOptions<ProjectContext> options) : base(options)
        {
            //var folder = Environment.SpecialFolder.LocalApplicationData;
            //var path = Environment.GetFolderPath(folder);
            DbPath = System.IO.Path.Join("", "db1.db");
        }

        protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
        {
            if (!optionsBuilder.IsConfigured)
            {
                optionsBuilder.UseSqlite($"Data Source={DbPath}");
            }
        }
    }
}
