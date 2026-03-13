// Tests in this file are NOT run in the PR pipeline. They are run in the continuous testing pipeline along with the ones in pr_test.go
package test

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func testRunBasicExample(t *testing.T, version string) {
	t.Parallel()

	options := setupOptions(t, "base-iks", basicExampleDir, iksVersion4)

	// Temp workaround for https://github.com/terraform-ibm-modules/terraform-ibm-base-ocp-vpc?tab=readme-ov-file#the-specified-api-key-could-not-be-found
	createContainersApikey(t, options.Region, resourceGroup)

	output, err := options.RunTestConsistency()

	assert.Nil(t, err, "This should not have errored")
	assert.NotNil(t, output, "Expected some output")
}

func TestRunBasicExample(t *testing.T) {
	t.Parallel()
	versions := []string{iksVersion3, iksVersion4}
	for _, version := range versions {
		t.Run(version, func(t *testing.T) { testRunBasicExample(t, version) })
	}
}
