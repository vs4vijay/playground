using System.ComponentModel.DataAnnotations;

namespace ProjectOne.DTOs
{
    public class CreateProjectDTO
    {
        [Required]
        [MaxLength(100)]
        public required string Name { get; set; }

        public string? Type { get; set; }
        public string[]? Promoters { get; set; }
        public string? District { get; set; }
        public DateTime? RegistrationDate { get; set; }
    }
}
