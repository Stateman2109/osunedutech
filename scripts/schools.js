async function getCurrentSchool(db) {
  // Get the actual domain currently being used
  let hostname = window.location.hostname
    .toLowerCase()
    .replace(/^www\./, "");

  console.log("================================");
  console.log("Browser hostname:", window.location.hostname);
  console.log("Normalized hostname:", hostname);
  console.log("================================");

  /*
   * LOCAL DEVELOPMENT
   *
   * When running on localhost, use Dee-perfect
   * as the default school for testing.
   *
   * Example:
   * 127.0.0.1:5500
   *        ↓
   * deeperfect-cbt.com.ng
   */
  if (hostname === "localhost" || hostname === "127.0.0.1") {
    hostname = "deeperfect-cbt.com.ng";

    console.log(
      "Local development detected."
    );

    console.log(
      "Using test school domain:",
      hostname
    );
  }

  console.log(
    "Searching school domain:",
    hostname
  );

  // Search Supabase for the school
  const { data, error } = await db
    .from("schools")
    .select("*")
    .eq("domain", hostname)
    .eq("is_active", true);

  // Database error
  if (error) {
    console.error(
      "School detection database error:",
      error
    );

    return null;
  }

  console.log(
    "School search result:",
    data
  );

  // No school found
  if (!data || data.length === 0) {
    console.error(
      "No active school found for domain:",
      hostname
    );

    return null;
  }

  // Duplicate domain
  if (data.length > 1) {
    console.error(
      "Multiple schools found for domain:",
      hostname
    );

    return null;
  }

  // School successfully detected
  const school = data[0];

  console.log(
    "School detected successfully:",
    school
  );

  console.log(
    "School Name:",
    school.school_name
  );

  console.log(
    "School ID:",
    school.id
  );

  console.log(
    "School Domain:",
    school.domain
  );

  return school;
}