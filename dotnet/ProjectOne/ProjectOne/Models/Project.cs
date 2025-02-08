using System.ComponentModel.DataAnnotations;

namespace ProjectOne.Models
{
    public class Project
    {
        [Key]
        public int Id { get; set; }
        //public Guid Id { get; set; }
        public string Name { get; set; }
        public string Type { get; set; }
        public string[] Promoters { get; set; }
        public string District { get; set; }
        public DateTime RegistrationDate { get; set; }
    }
}
