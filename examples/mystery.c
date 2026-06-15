#include <stdio.h>
int secret(int n){ int a=1; for(int i=2;i<=n;i++) a*=i; return a; }
int main(void){ printf("mystery says: factorial(6) = %d\n", secret(6)); return 0; }
